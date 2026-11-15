---
name: momentum
description: Read and change Sennheiser Momentum 4 headphone settings (battery, noise cancelling, transparency, equaliser, sound mode, codec, call behaviour) with the momentum CLI. Use when asked about the headset's battery or settings, or to change noise control, the equaliser, the Bluetooth codec or the call profile.
---

# momentum

The `momentum` CLI has no Code Mode namespace or MCP server, so use the CLI with `--json` where it takes it.

It talks to the first connected Bluetooth device named MOMENTUM over RFCOMM (`MOMENTUM_ADDRESS` picks one by address). When it says the headset isn't connected or can't be reached, tell the person to connect it and stop. Don't retry in a loop: commands take a shared lock, and only one runs at a time.

1. Read first with `momentum status --json`. A setting the firmware rejects is `null`: don't set it, and say it's unsupported.
2. `momentum set <setting> ...` changes one setting. `momentum set --help` lists them: `anc`, `adaptive`, `transparency`, `anti-wind`, `bass-boost`, `sound-mode`, `eq`, `eq-band`, `eq-preset`, `codec`, `call-profile-switch`, `auto-answer`, `auto-power-off`, `comfort-call`, `on-head-detection`, `smart-pause` and `touch-controls`.
3. Writes change the person's headset. Only run one when asked, and read `status --json` afterwards to confirm it. Before experimenting, note the current settings so they can be restored.
4. `codec` and `call-profile-switch` are PipeWire settings on the PC, not the headset. Picking a codec moves the headset to its A2DP profile, and the call profile switch applies to every Bluetooth headset.

Never use a GAIA command the CLI doesn't already expose. There is no firmware update, factory reset or device-forgetting command, and none must be added.
