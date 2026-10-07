import { Effect } from "effect";
import { GaiaError, Session } from "./Gaia.ts";

const Command = {
  battery: 0x0603,
  getAnc: 0x1a05,
  setAnc: 0x1a04,
  getTransparency: 0x1a03,
  setTransparency: 0x1a02,
  getNoiseTable: 0x1a01,
  setNoiseTable: 0x1a00,
} as const;

// One-byte switches, as [get, set] command pairs.
export const switches = {
  "auto-answer": [0x080b, 0x080a],
  "comfort-call": [0x0815, 0x0814],
  "on-head-detection": [0x0401, 0x0400],
  "smart-pause": [0x080d, 0x080c],
} as const;

export type Switch = keyof typeof switches;

// 0x1a01 is a table of (id, value) pairs and 0x1a00 writes it back whole, so
// changing one field is a read-modify-write.
const NoiseField = { antiWind: 1, adaptive: 5 } as const;

const NOISE_TABLE_LENGTH = 6;

export const antiWindModes = ["off", "max", "auto"] as const;

export type AntiWind = (typeof antiWindModes)[number];

export interface Status {
  readonly battery: number;
  readonly anc: boolean;
  readonly adaptive: boolean;
  readonly transparency: number;
  readonly antiWind: AntiWind | "unknown";
  readonly autoAnswer: boolean;
  readonly comfortCall: boolean;
  readonly onHeadDetection: boolean;
  readonly smartPause: boolean;
}

const firstByte = Effect.fnUntraced(function* (command: number) {
  const session = yield* Session;
  const payload = yield* session.request(command);
  const value = payload[0];

  if (value === undefined)
    return yield* new GaiaError({ message: "The headset sent an empty reply" });

  return value;
});

const writeByte = Effect.fnUntraced(function* (command: number, value: number) {
  const session = yield* Session;
  yield* session.request(command, Uint8Array.of(value));
});

const noiseTable = Effect.gen(function* () {
  const session = yield* Session;
  const table = yield* session.request(Command.getNoiseTable);

  if (table.length < NOISE_TABLE_LENGTH)
    return yield* new GaiaError({
      message: "The headset sent a short noise control table",
    });

  return table;
});

const writeNoiseField = Effect.fnUntraced(function* (
  index: number,
  value: number,
) {
  const session = yield* Session;
  const table = yield* noiseTable;
  table[index] = value;
  yield* session.request(Command.setNoiseTable, table);
});

export const status = Effect.gen(function* () {
  const table = yield* noiseTable;

  return {
    battery: yield* firstByte(Command.battery),
    anc: (yield* firstByte(Command.getAnc)) !== 0,
    adaptive: table[NoiseField.adaptive] !== 0,
    transparency: yield* firstByte(Command.getTransparency),
    antiWind: antiWindModes[table[NoiseField.antiWind] ?? -1] ?? "unknown",
    autoAnswer: (yield* firstByte(switches["auto-answer"][0])) !== 0,
    comfortCall: (yield* firstByte(switches["comfort-call"][0])) !== 0,
    onHeadDetection: (yield* firstByte(switches["on-head-detection"][0])) !== 0,
    smartPause: (yield* firstByte(switches["smart-pause"][0])) !== 0,
  } satisfies Status;
});

export const setAnc = (on: boolean) => writeByte(Command.setAnc, on ? 1 : 0);

export const setAdaptive = (on: boolean) =>
  writeNoiseField(NoiseField.adaptive, on ? 1 : 0);

export const setAntiWind = (mode: AntiWind) =>
  writeNoiseField(NoiseField.antiWind, antiWindModes.indexOf(mode));

export const setTransparency = (level: number) =>
  writeByte(Command.setTransparency, level);

export const setSwitch = (name: Switch, on: boolean) =>
  writeByte(switches[name][1], on ? 1 : 0);
