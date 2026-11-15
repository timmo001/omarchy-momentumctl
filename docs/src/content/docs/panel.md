---
title: Panel
description: Open and use the Momentum panel in the Omarchy shell.
---

The panel shows the headset battery and firmware version, the Bluetooth codec and sample rate PipeWire is using, and the controls the CLI offers. It talks to the headset only through the installed `momentum` executable.

Open it through its shell IPC target, and bind that command to a hotkey for direct access:

```bash
omarchy-shell shell toggle timmo.momentumctl
```

Up and Down move between controls, Enter activates the selected one, and Left and Right change the selected choice, level, preset or band. Enter on a band's value resets it to 0 dB. Type to filter the controls, and press Escape to clear the filter or close the panel.

Under Speech Clarity the panel disables bass boost and the equaliser, as Smart Control does.
