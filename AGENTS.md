# Omarchy MOMENTUM 4 Guidance

## Scope

- This repository owns the `timmo.momentumctl` Omarchy Shell panel plugin.
- The default branch is `main`.

## Plugin

- Keep the plugin self-contained at the repository root.
- Target Omarchy Quattro and the current user-plugin manifest contract.
- Run `mise run check` after changing QML or the manifest.
- The plugin talks to the headset only through the installed `momentumctl` executable.
- Keep commands serialized because each invocation opens a Bluetooth RFCOMM session.

## Safety

- Do not add firmware update, factory reset, or undocumented GAIA commands.
- The reverse-engineered control protocol can vary by firmware. Preserve clear disconnected and failed states.
