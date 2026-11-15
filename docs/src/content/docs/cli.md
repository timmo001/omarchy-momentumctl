---
title: CLI
description: The momentum commands and how the CLI finds the headset.
---

```bash
momentum status
momentum status --json
momentum set transparency 40
momentum set eq-preset harman
momentum set eq -3.5 -0.5 2.5 -0.5 -0.5
momentum set sound-mode speech
momentum set codec aac
momentum set call-profile-switch off
momentum --help
```

The CLI finds the first connected Bluetooth device named MOMENTUM. Set `MOMENTUM_ADDRESS` to pick one by address instead. Each command opens one Bluetooth session under a shared lock, so only one runs at a time.

`momentum status --json` prints every setting. One the firmware rejects is `null`.

## Settings

`momentum set --help` lists them: `anc`, `adaptive`, `transparency`, `anti-wind`, `bass-boost`, `sound-mode`, `eq`, `eq-band`, `eq-preset`, `codec`, `call-profile-switch`, `auto-answer`, `auto-power-off`, `comfort-call`, `on-head-detection`, `smart-pause` and `touch-controls`.

## Codec and call profile

These are PipeWire settings on the PC, not headset ones. Picking a codec switches the headset to its A2DP profile, which also leaves the call profile. The call profile switch is WirePlumber's `bluetooth.autoswitch-to-headset-profile`, saved with `wpctl`, so it applies to every Bluetooth headset. With it off, music stays in high quality but calls use another mic.

## Equaliser

The headset has five bands, labelled 63 Hz, 250 Hz, 1 kHz, 4 kHz and 8 kHz in Smart Control. Gains are in dB, in tenths. The presets are Smart Control's eight, plus a Harman preset fitted from AutoEq's Momentum 4 corrections. The curve is stored on the headset, so it carries over to other devices.
