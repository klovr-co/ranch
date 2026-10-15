# ranch

**One command turns any machine into part of your agent herd. Control them all from one device.**

Run Claude Code and Codex agents, CI and other heavy work on servers instead of your laptop. `ranch` gives every machine — your Mac, an old laptop, a cloud server — the same tools, the same agent rules and the same logins, and connects them on a private network so you can reach any of them from anywhere.

```bash
curl -fsSL https://raw.githubusercontent.com/xian-jun/ranch/main/install.sh | bash
```

That's it. Run the same line on the next machine, and the next.

## What you get on every machine

- **The same tools at the same versions** — Node, pnpm, `gh` and anything your team pins, via [mise](https://mise.jdx.dev)
- **Agents ready to go** — Claude Code and Codex installed and signed in
- **Your agent rules** — the same `CLAUDE.md` / `AGENTS.md` everywhere, so agents behave the same on every machine
- **A private network** — [Tailscale](https://tailscale.com) links your machines; nothing is exposed to the internet, and Linux machines accept SSH from your own devices only
- **Guided logins** — every sign-in is a link and a code, so a server with no screen is approved from your phone

## Commands

| Command | What it does |
|---|---|
| `ranch` | Set up or update this machine |
| `ranch --team owner/repo` | Add your team's config, then set up or update |
| `ranch login` | Sign in to anything missing (GitHub, Tailscale, Claude Code, Codex) |
| `ranch login status` | Show what's signed in |
| `ranch doctor` | Show what's installed |

Re-run `ranch` any time. It only changes what's different, and keeps itself up to date.

## Teams

Give everyone on a team the same setup with a team config — a private repo with three things:

```
your-org/ranch-config
  ranch.toml        # team name, secret manager
  mise.toml         # tools and versions for the team's repos
  agent/CLAUDE.md   # rules for Claude Code
  agent/AGENTS.md   # rules for Codex and other agents
```

```bash
curl -fsSL https://raw.githubusercontent.com/xian-jun/ranch/main/install.sh | bash -s -- --team your-org/ranch-config
```

Each team gets its own folder, `~/code/<team>/`. Its rules and tools apply only inside that folder, so you can belong to several teams on one machine without them mixing. Start from [`examples/team-config`](examples/team-config).

## Supported

macOS, Ubuntu, Debian and Fedora. Arch is best effort.

## Roadmap

- Secrets from your secret manager (Infisical first), injected at runtime — no `.env` files
- One-command cloud servers (DigitalOcean, Google Cloud)
- Self-hosted CI runners
- Agents that pick up GitHub issues on their own
