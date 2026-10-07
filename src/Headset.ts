import { Effect } from "effect";
import * as Audio from "./Audio.ts";
import { GaiaError, type GaiaRejected, Session } from "./Gaia.ts";

const Command = {
  battery: 0x0603,
  getAnc: 0x1a05,
  setAnc: 0x1a04,
  getTransparency: 0x1a03,
  setTransparency: 0x1a02,
  getNoiseTable: 0x1a01,
  setNoiseTable: 0x1a00,
  // A "disabled" flag, so 0 means the touch controls are on.
  getTouchControls: 0x1607,
  setTouchControls: 0x1606,
  // Both take a leading index byte (0); the value is seconds, 0 for never.
  getAutoPowerOff: 0x0601,
  setAutoPowerOff: 0x0600,
  // Three big-endian u16s: major, minor, patch.
  firmware: 0x1201,
  // The EQ has five fixed bands. Gains are signed tenths of a dB, set one
  // band at a time; the getter needs a (any) payload byte.
  setEqBand: 0x1001,
  getEq: 0x1003,
} as const;

export const EQ_BANDS = 5;

/** Smart Control's labels, which are nominal: the bands centre on 90, 325,
 * 1500, 6500 and 6500 Hz. */
export const eqBandLabels = ["63 Hz", "250 Hz", "1 kHz", "4 kHz", "8 kHz"];

export const eqPresetNames = [
  "neutral",
  "rock",
  "pop",
  "dance",
  "hip-hop",
  "classical",
  "movie",
  "jazz",
  "harman",
] as const;

export type EqPreset = (typeof eqPresetNames)[number];

// The app keeps presets itself and writes their gains, matching the active
// one by curve. Values from DanSmith888/omarchy-momentum4's presets.json.
export const eqPresets: Record<EqPreset, readonly number[]> = {
  neutral: [0, 0, 0, 0, 0],
  rock: [0, 2, 2.5, 1.5, -2],
  pop: [0, -2.5, 0, 2.5, 0],
  dance: [3.5, 2, -1.5, 1.5, 3],
  "hip-hop": [3, 1.5, -1.5, 0, -1.5],
  classical: [-2, -1.5, 0, 3.5, 4],
  movie: [0, 0, 2, 2, -2],
  jazz: [-3.2, 0, 2.2, 2.2, 0],
  // Not one of the app's. AutoEq's Harman corrections for the Momentum 4 from
  // RTINGS (B&K 5128) and oratory1990, averaged over a third of an octave at
  // the real band centres. The two top bands share 6.5 kHz, so they split
  // that band's cut.
  harman: [-3.5, -0.5, 2.5, -0.5, -0.5],
};

/** The byte range of a gain, in dB. */
export const EQ_GAIN_MIN = -12.8;

export const EQ_GAIN_MAX = 12.7;

export const autoPowerOffChoices = ["never", "15", "30", "60"] as const;

export type AutoPowerOff = (typeof autoPowerOffChoices)[number];

// One-byte switches, as [get, set] command pairs.
export const switches = {
  "auto-answer": [0x080b, 0x080a],
  "bass-boost": [0x1009, 0x1008],
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
  /** Null when the firmware rejects the command. */
  readonly bassBoost: boolean | null;
  readonly touchControls: boolean | null;
  /** Minutes, with 0 meaning never. */
  readonly autoPowerOff: number | null;
  readonly firmware: string | null;
  /** Gains in dB, one per band. */
  readonly eq: readonly number[] | null;
  /** The preset whose gains match the curve exactly. */
  readonly eqPreset: EqPreset | null;
  /** The Bluetooth codec PipeWire negotiated, and its sample rate in Hz. */
  readonly codec: string | null;
  readonly sampleRate: number | null;
}

// Newer settings can be missing on older firmware, so a rejection reports
// the setting as unsupported rather than failing the whole status.
const optional = <A, R>(
  effect: Effect.Effect<A, GaiaError | GaiaRejected, R>,
) => effect.pipe(Effect.catchTag("GaiaRejected", () => Effect.succeed(null)));

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

const autoPowerOff = Effect.gen(function* () {
  const session = yield* Session;

  const payload = yield* session.request(
    Command.getAutoPowerOff,
    Uint8Array.of(0),
  );

  if (payload.length < 3)
    return yield* new GaiaError({
      message: "The headset sent a short auto power off reply",
    });

  const seconds = new DataView(payload.buffer, payload.byteOffset).getUint16(1);

  return seconds / 60;
});

const firmware = Effect.gen(function* () {
  const session = yield* Session;
  const payload = yield* session.request(Command.firmware);

  if (payload.length < 6)
    return yield* new GaiaError({
      message: "The headset sent a short firmware reply",
    });

  const view = new DataView(payload.buffer, payload.byteOffset);

  return [0, 2, 4].map((offset) => view.getUint16(offset)).join(".");
});

const eq = Effect.gen(function* () {
  const session = yield* Session;
  const payload = yield* session.request(Command.getEq, Uint8Array.of(0));

  if (payload.length < EQ_BANDS)
    return yield* new GaiaError({
      message: "The headset sent a short EQ reply",
    });

  return [...new Int8Array(payload.buffer, payload.byteOffset, EQ_BANDS)].map(
    (gain) => gain / 10,
  );
});

const matchingPreset = (gains: readonly number[]) =>
  eqPresetNames.find((name) =>
    eqPresets[name].every((gain, band) => gain === gains[band]),
  ) ?? null;

export const status = Effect.gen(function* () {
  const session = yield* Session;
  const table = yield* noiseTable;
  const gains = yield* optional(eq);
  const stream = yield* Audio.stream(session.address);

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
    bassBoost: yield* optional(
      firstByte(switches["bass-boost"][0]).pipe(
        Effect.map((value) => value !== 0),
      ),
    ),
    touchControls: yield* optional(
      firstByte(Command.getTouchControls).pipe(
        Effect.map((value) => value === 0),
      ),
    ),
    autoPowerOff: yield* optional(autoPowerOff),
    firmware: yield* optional(firmware),
    eq: gains,
    eqPreset: gains === null ? null : matchingPreset(gains),
    ...stream,
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

export const setTouchControls = (on: boolean) =>
  writeByte(Command.setTouchControls, on ? 0 : 1);

export const setAutoPowerOff = Effect.fnUntraced(function* (
  choice: AutoPowerOff,
) {
  const session = yield* Session;
  const payload = new Uint8Array(3);
  const seconds = choice === "never" ? 0 : Number(choice) * 60;
  new DataView(payload.buffer).setUint16(1, seconds);
  yield* session.request(Command.setAutoPowerOff, payload);
});

export const setEqBand = Effect.fnUntraced(function* (
  band: number,
  gain: number,
) {
  const session = yield* Session;
  const payload = new Uint8Array(2);
  const view = new DataView(payload.buffer);
  view.setUint8(0, band);
  view.setInt8(1, Math.round(gain * 10));
  yield* session.request(Command.setEqBand, payload);
});

// There is no whole-curve setter, so this writes each band in turn, as
// Smart Control does when it applies a preset.
export const setEq = Effect.fnUntraced(function* (gains: readonly number[]) {
  for (const [band, gain] of gains.entries()) yield* setEqBand(band, gain);
});

export const setEqPreset = (name: EqPreset) => setEq(eqPresets[name]);
