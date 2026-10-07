import { BunRuntime, BunServices } from "@effect/platform-bun";
import { Console, Effect, Schema } from "effect";
import { Argument, Command, Flag } from "effect/cli";
import { type GaiaError, type GaiaRejected, Session } from "./Gaia.ts";
import * as Headset from "./Headset.ts";
import packageJson from "../package.json" with { type: "json" };

const onOff = (value: boolean | null) =>
  value === null ? "unsupported" : value ? "on" : "off";

const autoPowerOffLabel = (minutes: number | null) => {
  if (minutes === null) return "unsupported";

  return minutes === 0 ? "never" : `${minutes} minutes`;
};

const fail = (error: GaiaError | GaiaRejected) =>
  Console.error(`momentum: ${error.message}`).pipe(
    Effect.andThen(
      Effect.sync(() => {
        process.exitCode = 1;
      }),
    ),
  );

// Only commands that talk to the headset open a session, so help and
// version output work without one connected.
const withHeadset = <A>(
  effect: Effect.Effect<A, GaiaError | GaiaRejected, Session>,
) =>
  effect.pipe(
    Effect.provide(Session.layer),
    Effect.catch((error) => fail(error).pipe(Effect.as(undefined))),
  );

const toggle = {
  state: Argument.Literals("state", ["on", "off"] as const).pipe(
    Argument.map((state) => state === "on"),
  ),
};

const statusCommand = Command.make(
  "status",
  {
    json: Flag.Boolean("json").pipe(
      Flag.withDescription("Print the status as JSON"),
      Flag.withDefault(false),
    ),
  },
  Effect.fn(function* ({ json }) {
    const status = yield* withHeadset(Headset.status);

    if (status === undefined) return;

    if (json) return yield* Console.log(JSON.stringify(status));
    yield* Console.log(
      [
        `Battery: ${status.battery}%`,
        `ANC: ${onOff(status.anc)}`,
        `Adaptive: ${onOff(status.adaptive)}`,
        `Transparency: ${status.transparency}%`,
        `Anti-wind: ${status.antiWind}`,
        `Bass boost: ${onOff(status.bassBoost)}`,
        `Auto-answer: ${onOff(status.autoAnswer)}`,
        `Comfort call: ${onOff(status.comfortCall)}`,
        `On-head detection: ${onOff(status.onHeadDetection)}`,
        `Smart pause: ${onOff(status.smartPause)}`,
        `Touch controls: ${onOff(status.touchControls)}`,
        `Auto power off: ${autoPowerOffLabel(status.autoPowerOff)}`,
        `Firmware: ${status.firmware ?? "unknown"}`,
      ].join("\n"),
    );
  }),
).pipe(Command.withDescription("Show the headset's battery and settings"));

const switchCommand = (name: Headset.Switch, description: string) =>
  Command.make(name, toggle, ({ state }) =>
    withHeadset(Headset.setSwitch(name, state)),
  ).pipe(Command.withDescription(description));

const setCommand = Command.make("set").pipe(
  Command.withDescription("Change a headset setting"),
  Command.withSubcommands([
    Command.make("anc", toggle, ({ state }) =>
      withHeadset(Headset.setAnc(state)),
    ).pipe(Command.withDescription("Turn noise cancelling on or off")),
    Command.make("adaptive", toggle, ({ state }) =>
      withHeadset(Headset.setAdaptive(state)),
    ).pipe(
      Command.withDescription("Let the headset choose the transparency level"),
    ),
    Command.make(
      "transparency",
      {
        level: Argument.Int("level").pipe(
          Argument.withDescription("0 blocks the most, 100 lets the most in"),
          Argument.withSchema(
            Schema.Int.pipe(
              Schema.check(Schema.isBetween({ minimum: 0, maximum: 100 })),
            ),
          ),
        ),
      },
      ({ level }) => withHeadset(Headset.setTransparency(level)),
    ).pipe(Command.withDescription("Set the custom transparency level")),
    Command.make(
      "anti-wind",
      { mode: Argument.Literals("mode", Headset.antiWindModes) },
      ({ mode }) => withHeadset(Headset.setAntiWind(mode)),
    ).pipe(Command.withDescription("Set wind noise reduction")),
    switchCommand("auto-answer", "Answer calls when the headset is put on"),
    Command.make(
      "auto-power-off",
      { minutes: Argument.Literals("minutes", Headset.autoPowerOffChoices) },
      ({ minutes }) => withHeadset(Headset.setAutoPowerOff(minutes)),
    ).pipe(
      Command.withDescription("Turn the headset off after a while unused"),
    ),
    switchCommand("bass-boost", "Boost the low end"),
    switchCommand("comfort-call", "Hear your own voice during calls"),
    switchCommand(
      "on-head-detection",
      "Detect when the headset is put on or taken off",
    ),
    switchCommand("smart-pause", "Pause media when the headset is taken off"),
    Command.make("touch-controls", toggle, ({ state }) =>
      withHeadset(Headset.setTouchControls(state)),
    ).pipe(
      Command.withDescription("Turn the touch controls on the cup on or off"),
    ),
  ]),
);

const momentum = Command.make("momentum").pipe(
  Command.withDescription("Control Sennheiser Momentum 4 headphones"),
  Command.withSubcommands([statusCommand, setCommand]),
);

Command.run(momentum, { version: packageJson.version }).pipe(
  Effect.provide(BunServices.layer),
  BunRuntime.runMain,
);
