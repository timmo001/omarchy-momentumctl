# Omarchy MOMENTUM 4 Guidance

## Scope

- This repository owns the `timmo.momentumctl` Omarchy Shell plugin.
- It also owns the Arch package recipe for the upstream `momentumctl` CLI.
- The default branch is `main`.

## Plugin

- Keep the plugin self-contained at the repository root.
- Target Omarchy Quattro and the current user-plugin manifest contract.
- Run `mise run check` after changing QML or the manifest.
- The plugin talks to the headset only through the installed `momentumctl` executable.
- Keep commands serialized because each invocation opens a Bluetooth RFCOMM session.

## Packaging

- `PKGBUILD` packages the pinned upstream source release. Do not vendor or modify upstream Rust source here.
- Update the source revision and checksum together.
- Run `mise run package` after changing `PKGBUILD`.

## Safety

- Do not add firmware update, factory reset, or undocumented GAIA commands.
- The reverse-engineered control protocol can vary by firmware. Preserve clear disconnected and failed states.
