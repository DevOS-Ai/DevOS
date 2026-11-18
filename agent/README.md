# DevOS Agent

The operating-system agent of DevOS (SRS §14). It works at the user level (files,
projects, git, builds, terminals, web research, documents, subagents) and at the system
level through the DevOS system tools (desktop, apps, screenshots, system status, volume,
brightness, Wi-Fi, packages through polkit), right now or on a schedule.

| Path | What |
|---|---|
| `bin/devos-agent` | Command line and service entry point |
| `lib/init-home` | Per-user home: identity, config, local API port and key, `client.json` |
| `lib/provider.py` | `devos-agent setup-provider`: model provider and key (used by DevOS Settings) |
| `lib/launch.py` | Starts the packaged engine |
| `defaults/SOUL.md` | The agent's identity |
| `defaults/config.yaml` | Defaults: provider, approvals, DevOS system tools |
| `systemd/devos-agent.service` | User service, started with the desktop session |

The system tools are served by `devos mcp` from [devos-ai](../ai/devos/mcp.py). The
desktop clients are the DevOS AI panel ([desktop/devos-shell](../desktop/devos-shell))
and the shell sidebar. Package: [packaging/devos-agent](../packaging/devos-agent/PKGBUILD).

## How the pieces talk

```
DevOS AI panel / shell sidebar ──HTTP 127.0.0.1 (per-user key)──► devos-agent service
                                                                     │ runs, approvals,
                                                                     │ sessions, schedules
                                                                     ▼
                                              agent engine ──MCP stdio──► devos mcp
                                                                     (DevOS policy, polkit,
                                                                      audit log)
```

- Home: `~/.local/share/devos/agent` (`config.yaml`, `SOUL.md`, `.env`, sessions, memory,
  skills, schedules). `client.json` there tells the shell the URL and key.
- Approvals: risky terminal commands and every DevOS system tool that changes something
  arrive in the panel as Approve/Deny cards. Scheduled jobs never run them unattended.
- Logs: `journalctl --user -u devos-agent`; system tool calls also go to `devos audit`.

## Engine

The engine is an MIT-licensed open-source agent, pinned by commit in the PKGBUILD and
sealed (no self-update). Its license is installed as
`/usr/share/licenses/devos-agent/LICENSE.engine`.
