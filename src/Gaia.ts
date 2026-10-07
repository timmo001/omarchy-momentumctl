import {
  Context,
  Effect,
  Exit,
  FileSystem,
  Layer,
  Option,
  Schedule,
  Schema,
  Scope,
} from "effect";
import { ChildProcess, ChildProcessSpawner } from "effect/process";
import * as Rfcomm from "./Rfcomm.ts";

const MAGIC = [0xff, 0x03] as const;

const VENDOR_SENNHEISER = 0x0495;

const HEADER_LENGTH = 8;

const TIMEOUT_SECONDS = 3;

// GAIA is not always advertised cleanly over SDP, so probe the channels the
// headset is usually found on. A cached channel is tried first.
const CHANNELS = [1, 15, 2, 14, 12, 3, 4, 5, 6, 7, 8, 9, 10, 11] as const;

const PROBE_COMMAND = 0x1a05;

export class GaiaError extends Schema.TaggedError<GaiaError>()("GaiaError", {
  message: Schema.String,
}) {}

/** The headset answered with an error, usually an unsupported command. */
export class GaiaRejected extends Schema.TaggedError<GaiaRejected>()(
  "GaiaRejected",
  { command: Schema.Finite },
) {
  override get message() {
    return `The headset rejected command 0x${this.command.toString(16).padStart(4, "0")}`;
  }
}

interface Packet {
  readonly command: number;
  readonly payload: Uint8Array;
}

export function encode(command: number, payload: Uint8Array): Uint8Array {
  const frame = new Uint8Array(HEADER_LENGTH + payload.length);
  const view = new DataView(frame.buffer);
  frame.set(MAGIC, 0);
  view.setUint16(2, payload.length);
  view.setUint16(4, VENDOR_SENNHEISER);
  view.setUint16(6, command);
  frame.set(payload, HEADER_LENGTH);

  return frame;
}

/** Splits complete packets off the buffer and returns what is left over. */
export function decode(buffer: Uint8Array) {
  const packets: Packet[] = [];
  let offset = 0;

  while (buffer.length - offset >= HEADER_LENGTH) {
    if (buffer[offset] !== MAGIC[0] || buffer[offset + 1] !== MAGIC[1]) {
      offset++;
      continue;
    }

    const view = new DataView(buffer.buffer, buffer.byteOffset + offset);
    const total = HEADER_LENGTH + view.getUint16(2);

    if (buffer.length - offset < total) break;
    packets.push({
      command: view.getUint16(6),
      payload: buffer.slice(offset + HEADER_LENGTH, offset + total),
    });
    offset += total;
  }

  return { packets, rest: buffer.slice(offset) };
}

export interface SessionService {
  /** Sends a command and returns the payload of its reply. */
  readonly request: (
    command: number,
    payload?: Uint8Array,
  ) => Effect.Effect<Uint8Array, GaiaError | GaiaRejected>;
}

const transportError = (error: Rfcomm.RfcommError) =>
  new GaiaError({
    message: error.timedOut
      ? "The headset did not answer in time"
      : `Bluetooth ${error.message}`,
  });

function makeRequest(connection: Rfcomm.Connection): SessionService["request"] {
  let buffer: Uint8Array = new Uint8Array(0);

  return Effect.fnUntraced(function* (
    command: number,
    payload: Uint8Array = new Uint8Array(0),
  ) {
    yield* connection
      .write(encode(command, payload))
      .pipe(Effect.mapError(transportError));
    // Replies set bit 8 of the command, and errors also set bit 7.
    const success = command | 0x0100;
    const failure = command | 0x0180;

    for (;;) {
      const decoded = decode(buffer);
      buffer = decoded.rest;

      const reply = decoded.packets.find(
        (packet) => packet.command === success || packet.command === failure,
      );

      if (reply?.command === success) return reply.payload;

      if (reply) return yield* new GaiaRejected({ command });

      const chunk = yield* connection.read.pipe(
        Effect.mapError(transportError),
      );

      if (chunk.length === 0)
        return yield* new GaiaError({
          message: "The headset closed the connection",
        });
      const next = new Uint8Array(buffer.length + chunk.length);
      next.set(buffer);
      next.set(chunk, buffer.length);
      buffer = next;
    }
  });
}

const connectedHeadset = Effect.gen(function* () {
  const configured = process.env["MOMENTUM_ADDRESS"];

  if (configured) return configured;

  const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;

  const lines = yield* spawner
    .lines(ChildProcess.make("bluetoothctl", ["devices", "Connected"]))
    .pipe(
      Effect.mapError(
        () => new GaiaError({ message: "Could not run bluetoothctl" }),
      ),
    );

  for (const line of lines) {
    const [, address, name] = /^Device (\S+) (.*)$/.exec(line) ?? [];

    if (address && name?.toUpperCase().includes("MOMENTUM")) return address;
  }

  return yield* new GaiaError({ message: "No Momentum headset is connected" });
});

const runtimeDirectory = Effect.gen(function* () {
  const base = process.env["XDG_RUNTIME_DIR"];

  if (!base)
    return yield* new GaiaError({ message: "XDG_RUNTIME_DIR is not set" });
  const directory = `${base}/momentum`;
  const fs = yield* FileSystem.FileSystem;
  yield* fs
    .makeDirectory(directory, { recursive: true, mode: 0o700 })
    .pipe(
      Effect.mapError(
        () => new GaiaError({ message: `Could not create ${directory}` }),
      ),
    );

  return directory;
});

// Only one process can hold the GAIA channel, so the panel and a terminal
// wait for each other instead of breaking each other's session.
const holdLock = Effect.fnUntraced(function* (directory: string) {
  const fd = yield* Rfcomm.openLockFile(`${directory}/lock`).pipe(
    Effect.mapError(
      () => new GaiaError({ message: "Could not open the lock file" }),
    ),
  );

  yield* Rfcomm.tryLock(fd).pipe(
    Effect.mapError(transportError),
    Effect.filterOrFail(
      (locked) => locked,
      () => new GaiaError({ message: "Another process is using the headset" }),
    ),
    Effect.retry(
      Schedule.spaced("250 millis").pipe(
        Schedule.upTo({ duration: "30 seconds" }),
      ),
    ),
  );
});

// Each attempt gets its own scope, so a channel that connects but doesn't
// speak GAIA is closed straight away rather than when the session ends.
const openSession = Effect.fnUntraced(function* (
  address: string,
  channel: number,
) {
  const scope = yield* Scope.fork(yield* Scope.Scope);

  return yield* Effect.gen(function* () {
    const connection = yield* Rfcomm.connect(address, channel, TIMEOUT_SECONDS);
    const request = makeRequest(connection);
    yield* request(PROBE_COMMAND);

    return request;
  }).pipe(
    Scope.provide(scope),
    Effect.onError(() => Scope.close(scope, Exit.void)),
  );
});

export class Session extends Context.Service<Session, SessionService>()(
  "momentum/Gaia/Session",
) {
  static readonly layer = Layer.effect(
    Session,
    Effect.gen(function* () {
      const fs = yield* FileSystem.FileSystem;
      const address = yield* connectedHeadset;
      const directory = yield* runtimeDirectory;
      yield* holdLock(directory);

      const cacheFile = `${directory}/channel-${address.replaceAll(":", "")}`;

      const cached = yield* fs.readFileString(cacheFile).pipe(
        Effect.map((text) => Number.parseInt(text.trim(), 10)),
        Effect.orElseSucceed(() => Number.NaN),
      );

      const channels = Number.isInteger(cached)
        ? [cached, ...CHANNELS.filter((channel) => channel !== cached)]
        : CHANNELS;

      for (const channel of channels) {
        // A refused connection or a reply that isn't GAIA means the wrong
        // channel. Anything else, such as a timeout, means the headset itself
        // is out of reach, so trying the other channels would only add waits.
        const request = yield* openSession(address, channel).pipe(
          Effect.asSome,
          Effect.catchTags({
            GaiaError: () => Effect.succeedNone,
            GaiaRejected: () => Effect.succeedNone,
            RfcommError: (error) =>
              error.refused
                ? Effect.succeedNone
                : Effect.fail(
                    new GaiaError({
                      message: error.timedOut
                        ? "The headset is not responding"
                        : `The headset is unreachable (${error.message})`,
                    }),
                  ),
          }),
        );

        if (Option.isNone(request)) continue;

        if (channel !== cached)
          yield* fs
            .writeFileString(cacheFile, String(channel))
            .pipe(Effect.ignore);

        return Session.of({ request: request.value });
      }

      return yield* new GaiaError({
        message: `No GAIA channel answered on ${address}`,
      });
    }),
  );
}
