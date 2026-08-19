# MOMENTUM 4 for Omarchy

An Omarchy bar widget and control panel for Sennheiser MOMENTUM 4 headphones.
It shows the headset battery and controls ANC, adaptive noise control,
transparency, anti-wind mode, Smart Pause, on-head detection, auto-answer, and
Comfort Call.

## Requirements

- Omarchy Quattro
- `momentumctl` installed and available on `PATH`
- A paired and connected Sennheiser MOMENTUM 4 headset

`momentumctl` uses a reverse-engineered Sennheiser protocol. Features may vary
with headset firmware. This plugin does not implement firmware updates, factory
resets, or undocumented commands.

## Install

Review the plugin, then install it:

```bash
omarchy plugin add https://github.com/timmo001/omarchy-momentumctl.git
```

For an unattended install from a repository you already trust:

```bash
omarchy plugin add \
  https://github.com/timmo001/omarchy-momentumctl.git \
  --enable --yes
```

Select the headphones widget to open the panel. The plugin also exposes the
`timmo.momentumctl` shell IPC target:

```bash
omarchy-shell timmo.momentumctl toggle
```

## Update

```bash
omarchy plugin update timmo.momentumctl
```

## Remove

```bash
omarchy plugin remove timmo.momentumctl
```

## Validate

```bash
mise run check
```

## Credits

The CLI is maintained by [Galen Abell](https://github.com/gjabell/momentumctl)
and distributed separately under the MIT licence. The headset protocol was
reverse-engineered by community contributors and is not an official Sennheiser
API.
