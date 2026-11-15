---
title: Agents
description: Let an agent read and change the headset through the momentum CLI.
---

The repository ships a tool-owned skill, [`skills/momentum/SKILL.md`](https://github.com/timmo001/omarchy-momentumctl/blob/main/skills/momentum/SKILL.md). It tells an agent to read with `momentum status --json`, change one setting at a time with `momentum set`, and check the result afterwards.

The CLI has no Code Mode namespace or MCP server yet, so agents use it directly. They never use a GAIA command the CLI doesn't expose, and none can update the firmware, factory reset the headset or forget a paired device.

This documentation site has its own MCP server at <https://momentumctl.timmo.dev/mcp>.
