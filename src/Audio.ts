import { Effect, Option, Predicate, Schema } from "effect";
import { ChildProcess, ChildProcessSpawner } from "effect/process";

const Sinks = Schema.fromJsonString(
  Schema.Array(
    Schema.Struct({
      sample_specification: Schema.String,
      properties: Schema.Record(Schema.String, Schema.Unknown),
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

export interface Stream {
  readonly codec: string | null;
  /** Hz. */
  readonly sampleRate: number | null;
}

const unknown: Stream = { codec: null, sampleRate: null };

/** What PipeWire negotiated with the headset, read from its Bluetooth sink.
 * The PC decides this, not the headset, so it comes from pactl. */
export const stream = Effect.fnUntraced(function* (address: string) {
  const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;

  const output = yield* spawner
    .string(ChildProcess.make("pactl", ["--format=json", "list", "sinks"]))
    .pipe(Effect.option);

  if (Option.isNone(output)) return unknown;

  const sinks = Schema.decodeOption(Sinks)(output.value);

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
