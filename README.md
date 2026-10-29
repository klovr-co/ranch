# ranch

**One command turns any machine into part of your agent herd. Control them all from one device.**

Run Claude Code and Codex agents, CI and other heavy work on servers instead of your laptop. `ranch` gives every machine — your Mac, an old laptop, a cloud server — the same tools, the same agent rules and the same logins, and connects them on a private network so you can reach any of them from anywhere.

```bash
curl -fsSL klovr-co.github.io/ranch | bash
```

That's it. Run the same line on the next machine, and the next.

On Windows 11 (PowerShell):

```powershell
irm klovr-co.github.io/ranch/install.ps1 | iex
```

## What you get on every machine

- **The same tools at the same versions** — Node, pnpm, `gh` and anything your team pins, via [mise](https://mise.jdx.dev)
- **Agents ready to go** — Claude Code and Codex installed and signed in
- **Your agent rules** — the same `CLAUDE.md` / `AGENTS.md` everywhere, so agents behave the same on every machine
- **A private network** — [Tailscale](https://tailscale.com) links your machines; nothing is exposed to the internet, and Linux machines accept SSH from your own devices only
- **Guided logins** — every sign-in is a link and a code, so a server with no screen is approved from your phone
- **[T3 Code](https://t3.codes) on servers** — running in the background and reachable only from your own devices, so you drive every server's agents from the T3 app on your main computer or phone (skip with `RANCH_T3=0`; nightly builds with `RANCH_T3_CHANNEL=nightly`)

## Commands

| Command | What it does |
|---|---|
| `ranch` | Set up or update this machine |
| `ranch --team owner/repo` | Add your team's config, then set up or update |
| `ranch login` | Sign in to anything missing (GitHub, Tailscale, Google Cloud, Claude Code, Codex) |
| `ranch login status` | Show what's signed in |
| `ranch doctor` | Show what's installed |
| `ranch status` | This machine, every device on your network, and every server you've added |
| `ranch update` | Update every server you've added to the newest ranch (logins untouched) |
| `ranch run -- <command>` | Run a command with its secrets from Infisical, e.g. `ranch run -- pnpm dev`. No `.env` files |
| `ranch secrets connect [user@]machine` | From your main computer: give a server its own limited Infisical login |
| `ranch secrets grant [machine]` | From your main computer: let servers you already connected see projects added since, without new keys |
| `ranch secrets import <env> --from-convex DEPLOYMENT` (or `--from-file PATH`, or `--from-cloudrun SERVICE --project P --region R`) | First time in a repo: load its existing secrets into that Infisical environment. Shows names only, asks first, keeps existing values unless `--overwrite`, never deletes. Needs your own login |
| `--path /folder` (on import, push, status) | Which Infisical folder to use. Default: `path:` in `.ranch/secrets.yaml`, else the root. One-app repos need nothing; repos with several apps use `/backend`, `/web` and so on |
| `ranch secrets push <env>` | In a repo with `.ranch/secrets.yaml`: copy that Infisical environment to its Convex deployment (shows names only, asks first, never deletes) |
| `ranch secrets status <env>` | Same check without changing anything; exits 1 if the two differ |
| `ranch join` | At a new Linux server: join your network by scanning a QR code |
| `ranch add [user@]machine` | From your main computer: set that server up remotely, logins carried over |
| `ranch pair [user@]machine` | From your main computer: a fresh link to pair that server with your T3 Code app |

Re-run `ranch` any time. It only changes what's different, and keeps itself up to date.

## Adding a server from your main computer *(new)*

Signing in on a server with no screen means copying links and codes by hand. Instead, do one step at the server and everything else from your main computer, where links are clickable:

**1. At the new server — one line, one scan**

```bash
curl -fsSL klovr-co.github.io/ranch | bash -s -- join
```

This installs only Tailscale and shows a QR code. Scan it with your phone and approve. Nothing to type or copy.

**2. On your main computer — one command**

```bash
ranch add <machine-name>
```

`ranch` connects to the server over Tailscale SSH and sets it up remotely, carrying your logins over:

| Login | How it's done |
|---|---|
| Tailscale | Already done in step 1 |
| GitHub | No clicks: your main computer passes its GitHub login over the secure connection. `git@github.com:` URLs are rewritten to HTTPS, so clones work without SSH keys |
| Codex | No clicks: your Codex sign-in is copied over, as Codex recommends for headless machines |
| Claude Code | One click: the sign-in link opens in your main computer's browser |
| Infisical | No clicks: the server gets its own limited Infisical login, created from your main computer. Revoke one server without touching the rest |
| T3 Code | One paste: the pairing link is copied and the T3 app opened; paste it into Settings → Connections → Add environment |

One QR scan, one click and one paste, instead of copying links and codes by hand.

> The server signs in as you, with the same accounts as your main computer. That's right for machines you own. Shared or cloud servers should get their own limited logins.

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
curl -fsSL klovr-co.github.io/ranch | bash -s -- --team your-org/ranch-config
```

Each team gets its own folder, `~/code/<team>/`. Its rules and tools apply only inside that folder, so you can belong to several teams on one machine without them mixing. Start from [`examples/team-config`](examples/team-config).

## Supported

macOS, Ubuntu, Debian and Fedora. Arch is best effort.

**Windows 11 (x64 and ARM64), early support.** `ranch`, `ranch login`, `ranch login status` and `ranch doctor` set up the machine with winget: git, gh, gcloud, uv, Node, pnpm, Claude Code, Codex and Tailscale. T3 Code is installed too; `ranch pair` on the Windows machine prints a link to paste into the T3 app on your main computer. Not on Windows yet: `--team`, `status`, `update`, `run`, `secrets`, `join`, `add`.

## Roadmap

- Secrets per repo from Infisical, injected at runtime — no `.env` files (Infisical is installed and signed in already)
- One-command cloud servers (DigitalOcean, Google Cloud)
- Self-hosted CI runners
- Agents that pick up GitHub issues on their own
