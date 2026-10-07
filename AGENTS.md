# Momentum Guidance

## Scope

- This repository owns the `momentum` CLI and the `timmo.momentumctl` Omarchy Shell panel plugin.
- The default branch is `main`.

## CLI

- The CLI lives in `src/`, uses Effect, and is compiled with Bun into a single `momentum` binary.
- Add no runtime dependencies beyond Effect and its Bun platform package. Pin dependencies to exact versions.
- RFCOMM sockets and file locks go through `bun:ffi` in `src/Rfcomm.ts`.
- Every command that talks to the headset takes the shared lock, so only one RFCOMM session is open at a time.
- Report settings the firmware rejects as `null`, so the panel can hide them.

## Plugin

- Keep the plugin self-contained at the repository root.
- Target Omarchy Quattro and the current user-plugin manifest contract.
- The plugin talks to the headset only through the installed `momentum` executable, using `momentum status --json` and `momentum set`.
- Keep commands serialized because each invocation opens a Bluetooth RFCOMM session.

## Checks

- Run `mise run check` after changing the CLI, QML or the manifest.
- Test headset changes against a real headset and restore the previous settings afterwards.

## Safety

- Only use GAIA commands documented in DanSmith888/omarchy-momentum4's `PROTOCOL.md` and already used by the CLI.
- Never send `0x0607` (knocks the headset offline), `0x1403` (forgets a paired device), or sweeps of `0x06xx`.
- Do not add firmware update or factory reset commands.
- The reverse-engineered control protocol can vary by firmware. Preserve clear disconnected and failed states.
