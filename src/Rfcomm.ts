import { dlopen, FFIType, ptr, read as readPointer } from "bun:ffi";
import { Effect, Schema, Scope } from "effect";

const AF_BLUETOOTH = 31;

const SOCK_STREAM = 1;

const SOCK_CLOEXEC = 0x80000;

const BTPROTO_RFCOMM = 3;

const SOL_SOCKET = 1;

const SO_RCVTIMEO = 20;

const SO_SNDTIMEO = 21;

const EAGAIN = 11;

const EINTR = 4;

const ECONNREFUSED = 111;

const ETIMEDOUT = 110;

// A blocking connect that runs past SO_SNDTIMEO.
const EINPROGRESS = 115;

const libc = dlopen("libc.so.6", {
  socket: {
    args: [FFIType.i32, FFIType.i32, FFIType.i32],
    returns: FFIType.i32,
  },
  connect: {
    args: [FFIType.i32, FFIType.ptr, FFIType.u32],
    returns: FFIType.i32,
  },
  setsockopt: {
    args: [FFIType.i32, FFIType.i32, FFIType.i32, FFIType.ptr, FFIType.u32],
    returns: FFIType.i32,
  },
  write: {
    args: [FFIType.i32, FFIType.ptr, FFIType.u64],
    returns: FFIType.i64,
  },
  read: {
    args: [FFIType.i32, FFIType.ptr, FFIType.u64],
    returns: FFIType.i64,
  },
  close: { args: [FFIType.i32], returns: FFIType.i32 },
  flock: { args: [FFIType.i32, FFIType.i32], returns: FFIType.i32 },
  open: {
    args: [FFIType.ptr, FFIType.i32, FFIType.u32],
    returns: FFIType.i32,
  },
  __errno_location: { args: [], returns: FFIType.ptr },
}).symbols;

export class RfcommError extends Schema.TaggedError<RfcommError>()(
  "RfcommError",
  {
    operation: Schema.String,
    errno: Schema.Finite,
  },
) {
  override get message() {
    return `${this.operation} failed (errno ${this.errno})`;
  }

  get timedOut() {
    return [EAGAIN, EINPROGRESS, ETIMEDOUT].includes(this.errno);
  }

  /** The device answered but nothing is listening on that channel. */
  get refused() {
    return this.errno === ECONNREFUSED;
  }
}

export interface Connection {
  readonly write: (data: Uint8Array) => Effect.Effect<void, RfcommError>;
  /** Waits up to the socket timeout and succeeds with no bytes on EOF. */
  readonly read: Effect.Effect<Uint8Array, RfcommError>;
}

function errno(): number {
  const location = libc.__errno_location();

  return location === null ? 0 : readPointer.i32(location);
}

function socketAddress(address: string, channel: number): Uint8Array {
  const bytes = address.split(":").map((part) => Number.parseInt(part, 16));
  const buffer = new Uint8Array(10);
  new DataView(buffer.buffer).setUint16(0, AF_BLUETOOTH, true);
  // bdaddr_t is stored little-endian, so the colon-separated bytes reverse.
  bytes.reverse().forEach((value, index) => {
    buffer[2 + index] = value;
  });
  buffer[8] = channel;

  return buffer;
}

function setTimeout(fd: number, option: number, seconds: number): boolean {
  const timeval = new BigInt64Array([BigInt(seconds), 0n]);

  return libc.setsockopt(fd, SOL_SOCKET, option, ptr(timeval), 16) === 0;
}

const failure = (operation: string) =>
  new RfcommError({ operation, errno: errno() });

/** Opens an RFCOMM stream that closes with the surrounding scope. */
export const connect = (
  address: string,
  channel: number,
  timeoutSeconds: number,
): Effect.Effect<Connection, RfcommError, Scope.Scope> =>
  Effect.gen(function* () {
    // A failed attempt closes its socket straight away, so probing several
    // channels doesn't leave descriptors open until the scope ends.
    const fd = yield* Effect.acquireRelease(
      Effect.suspend(() => {
        const fd = libc.socket(
          AF_BLUETOOTH,
          SOCK_STREAM | SOCK_CLOEXEC,
          BTPROTO_RFCOMM,
        );

        if (fd < 0) return Effect.fail(failure("socket"));
        const addressBuffer = socketAddress(address, channel);

        const error = !(
          setTimeout(fd, SO_RCVTIMEO, timeoutSeconds) &&
          setTimeout(fd, SO_SNDTIMEO, timeoutSeconds)
        )
          ? failure("setsockopt")
          : libc.connect(fd, ptr(addressBuffer), addressBuffer.length) !== 0
            ? failure("connect")
            : undefined;

        if (error === undefined) return Effect.succeed(fd);
        libc.close(fd);

        return Effect.fail(error);
      }),
      (fd) => Effect.sync(() => libc.close(fd)),
    );

    const buffer = new Uint8Array(1024);

    return {
      write: (data) =>
        Effect.suspend(() => {
          let offset = 0;

          while (offset < data.length) {
            const written = Number(
              libc.write(fd, ptr(data, offset), data.length - offset),
            );

            if (written < 0) {
              if (errno() === EINTR) continue;

              return Effect.fail(failure("write"));
            }

            offset += written;
          }

          return Effect.void;
        }),
      read: Effect.suspend(() => {
        for (;;) {
          const count = Number(libc.read(fd, ptr(buffer), buffer.length));

          if (count >= 0) return Effect.succeed(buffer.slice(0, count));

          if (errno() !== EINTR) return Effect.fail(failure("read"));
        }
      }),
    } satisfies Connection;
  });

const LOCK_EX = 2;

const LOCK_NB = 4;

const O_RDWR = 0x2;

const O_CREAT = 0x40;

const O_NOFOLLOW = 0x20000;

const O_CLOEXEC = 0x80000;

/** Opens a lock file that closes, releasing any lock, with the scope. */
export const openLockFile = (
  path: string,
): Effect.Effect<number, RfcommError, Scope.Scope> =>
  Effect.acquireRelease(
    Effect.suspend(() => {
      const fd = libc.open(
        ptr(Buffer.from(`${path}\0`)),
        O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
        0o600,
      );

      return fd < 0 ? Effect.fail(failure("open")) : Effect.succeed(fd);
    }),
    (fd) => Effect.sync(() => libc.close(fd)),
  );

/** Takes an exclusive, non-blocking flock; false means another holder. */
export const tryLock = (fd: number): Effect.Effect<boolean, RfcommError> =>
  Effect.suspend(() => {
    if (libc.flock(fd, LOCK_EX | LOCK_NB) === 0) return Effect.succeed(true);

    return errno() === EAGAIN
      ? Effect.succeed(false)
      : Effect.fail(failure("flock"));
  });
