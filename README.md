# momentumctl for Omarchy

An Omarchy control panel for Sennheiser headphones supported by `momentumctl`. It shows the
headset battery and controls ANC, adaptive noise control,
transparency, anti-wind mode, Smart Pause, on-head detection, auto-answer, and
Comfort Call.

<img width="710" height="1115" alt="image" src="https://github.com/user-attachments/assets/2357d176-d6e7-4f50-98d5-3db27094d272" />

## Requirements

- Omarchy Quattro
- `momentumctl` installed and available on `PATH`
- A paired and connected Sennheiser headset supported by `momentumctl`

`momentumctl` uses a reverse-engineered Sennheiser protocol. Features may vary
with headset firmware. This plugin does not implement firmware updates, factory
resets, or undocumented commands.

## Install

Install `momentumctl` with mise:

```bash
mise use --global cargo:https://codeberg.org/galen/momentumctl@rev:e86f3e22a0278892c073d1a9f956e5976839c661
```

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

Open the panel through its shell IPC target:

```bash
omarchy-shell shell toggle timmo.momentumctl
```

Bind that command to a desktop hotkey for direct access.

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
