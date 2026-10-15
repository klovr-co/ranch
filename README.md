# setup

Make any machine ready to work in minutes: the same tools, agent settings and logins on macOS and Linux.

```bash
curl -fsSL https://raw.githubusercontent.com/xian-jun/setup/main/install.sh | bash
# with a team config:
curl -fsSL https://raw.githubusercontent.com/xian-jun/setup/main/install.sh | bash -s -- --team your-org/setup-config
```

Safe to re-run any time: it only changes what's different.

## Commands

| Command | What it does |
|---|---|
| `setup` | Install or update everything |
| `setup --team owner/repo` | Add a team config, then install or update |
| `setup login` | Sign in to anything missing (GitHub, Claude Code, Codex, …) |
| `setup login status` | Show what's signed in |
| `setup doctor` | Show what's installed |

## What it installs

- [mise](https://mise.jdx.dev) for pinned tool versions, plus `gh` and Node
- Claude Code and Codex (left alone if already installed)
- Tailscale, so your machines reach each other privately (Linux machines accept SSH from your devices)
- Your team's agent rules and tools, scoped to `~/code/<team>/`

## Team configs

A team config is a private repo with `setup.toml`, `mise.toml` and `agent/` rules. Start from [`examples/team-config`](examples/team-config).

## Supported

macOS, Ubuntu, Debian, Fedora. Arch is best effort.

> Work in progress: secret manager support is coming next.
