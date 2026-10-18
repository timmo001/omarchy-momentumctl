import { Effect, Option, Predicate, Schema } from "effect";
import { ChildProcess, ChildProcessSpawner } from "effect/process";

export class AudioError extends Schema.TaggedError<AudioError>()("AudioError", {
  message: Schema.String,
}) {}

const Sinks = Schema.fromJsonString(
  Schema.Array(
    Schema.Struct({
      sample_specification: Schema.String,
      properties: Schema.Record(Schema.String, Schema.Unknown),
    }),
  ),
);

const Cards = Schema.fromJsonString(
  Schema.Array(
    Schema.Struct({
      name: Schema.String,
      properties: Schema.Record(Schema.String, Schema.Unknown),
      profiles: Schema.Record(
        Schema.String,
        Schema.Struct({
          description: Schema.String,
          available: Schema.Boolean,
        }),
      ),
    }),
  ),
);

const codecNames = new Map([
  ["sbc", "SBC"],
  ["sbc_xq", "SBC-XQ"],
  ["aac", "AAC"],
  ["aptx", "aptX"],
  ["aptx_hd", "aptX HD"],
  ["aptx_ll", "aptX LL"],
  ["ldac", "LDAC"],
  ["lc3", "LC3"],
  ["opus_05", "Opus"],
]);

const AUTOSWITCH_SETTING = "bluetooth.autoswitch-to-headset-profile";

// pipewire-pulse answers with JSON, null when WirePlumber doesn't support it.
const AutoswitchReply = Schema.fromJsonString(Schema.NullOr(Schema.Boolean));

export interface Stream {
  readonly codec: string | null;
  /** Hz. */
  readonly sampleRate: number | null;
}

export interface Audio extends Stream {
  /** The A2DP codecs PipeWire offers for the headset, by name. */
  readonly codecs: readonly string[];
  /** Whether WirePlumber moves Bluetooth headsets to the call profile when
   * an app records from them. Null when pipewire-pulse doesn't say. */
  readonly callProfileSwitch: boolean | null;
}

const unknown: Stream = { codec: null, sampleRate: null };

const run = Effect.fnUntraced(function* (command: string, args: string[]) {
  const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;

  return yield* spawner
    .string(ChildProcess.make(command, args))
    .pipe(Effect.option);
});

const pactlJson = <A>(schema: Schema.Codec<A, string>, what: string) =>
  run("pactl", ["--format=json", "list", what]).pipe(
    Effect.map(Option.flatMap(Schema.decodeOption(schema))),
  );

/** What PipeWire negotiated with the headset, read from its Bluetooth sink.
 * The PC decides this, not the headset, so it comes from pactl. */
const stream = Effect.fnUntraced(function* (address: string) {
  const sinks = yield* pactlJson(Sinks, "sinks");

  if (Option.isNone(sinks)) return unknown;

  const sink = sinks.value.find(
    (candidate) =>
      candidate.properties["api.bluez5.address"] === address.toUpperCase(),
  );

  if (!sink) return unknown;

  const codec = sink.properties["api.bluez5.codec"];
  const rate = /(\d+)Hz/.exec(sink.sample_specification)?.[1];

  return {
    codec: Predicate.isString(codec) ? (codecNames.get(codec) ?? codec) : null,
    sampleRate: rate === undefined ? null : Number(rate),
  } satisfies Stream;
});

// Each A2DP codec is its own card profile, so picking one also leaves the
// call profile. The bare a2dp-sink profile is the best codec, and only its
// description names it.
const codecProfiles = Effect.fnUntraced(function* (address: string) {
  const cards = yield* pactlJson(Cards, "cards");

  const card = Option.getOrUndefined(cards)?.find(
    (candidate) =>
      candidate.properties["api.bluez5.address"] === address.toUpperCase(),
  );

  if (!card) return null;

  const profiles = Object.entries(card.profiles).flatMap(([profile, info]) => {
    const codec = /codec (.+)\)$/.exec(info.description)?.[1];

    return profile.startsWith("a2dp-sink") && info.available && codec
      ? [{ codec, profile }]
      : [];
  });

  return { card: card.name, profiles };
});

const callProfileSwitch = run("pactl", [
  "send-message",
  "/core",
  "pipewire-pulse:bluetooth-headset-autoswitch",
]).pipe(
  Effect.map((output) =>
    Option.getOrNull(
      Option.flatMap(output, Schema.decodeOption(AutoswitchReply)),
    ),
  ),
);

export const status = Effect.fnUntraced(function* (address: string) {
  const codecs = yield* codecProfiles(address);

  return {
    ...(yield* stream(address)),
    codecs: codecs?.profiles.map(({ codec }) => codec) ?? [],
    callProfileSwitch: yield* callProfileSwitch,
  } satisfies Audio;
});

const normalise = (codec: string) =>
  codec.toLowerCase().replaceAll(/[^a-z0-9]/g, "");

const succeeded = Effect.fnUntraced(function* (
  command: string,
  args: string[],
  message: string,
) {
  const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;

  const exitCode = yield* spawner
    .exitCode(ChildProcess.make(command, args))
    .pipe(Effect.mapError(() => new AudioError({ message })));

  if (exitCode !== 0) return yield* new AudioError({ message });
});

/** Switches the headset to an A2DP codec, matched by name ignoring case and
 * punctuation, so "aptx-hd" picks aptX HD. */
export const setCodec = Effect.fnUntraced(function* (
  address: string,
  name: string,
) {
  const codecs = yield* codecProfiles(address);

  if (codecs === null)
    return yield* new AudioError({
      message: "PipeWire has no audio device for the headset",
    });

  const match = codecs.profiles.find(
    ({ codec }) => normalise(codec) === normalise(name),
  );

  if (!match)
    return yield* new AudioError({
      message: `The headset doesn't offer ${name}. Choose from ${codecs.profiles.map(({ codec }) => codec).join(", ")}`,
    });

  yield* succeeded(
    "pactl",
    ["set-card-profile", codecs.card, match.profile],
    `Could not switch to ${match.codec}`,
  );
});

/** Saves WirePlumber's switch to the call profile, which applies to every
 * Bluetooth headset. */
export const setCallProfileSwitch = (on: boolean) =>
  succeeded(
    "wpctl",
    ["settings", "--save", AUTOSWITCH_SETTING, String(on)],
    "Could not change the WirePlumber setting",
  );
