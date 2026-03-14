# claude-danger-lab

[![Build](https://github.com/CheeryProgrammer/claude-danger-lab/actions/workflows/build.yml/badge.svg)](https://github.com/CheeryProgrammer/claude-danger-lab/actions/workflows/build.yml)

Isolated Docker container for running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in dangerous mode — no permission prompts, full autonomy, persistent sessions. Connect from anywhere over SSH.

---

## Setup

**1. Clone and configure**

```bash
git clone https://github.com/CheeryProgrammer/claude-danger-lab.git
cd claude-danger-lab
cp .env.example .env
```

Open `.env` and fill in:

```bash
# Your SSH public key — get it with: cat ~/.ssh/id_ed25519.pub
SSH_PUBLIC_KEY=ssh-ed25519 AAAA...
```

**2. Add your projects** — edit `projects.conf`:

```
# name          git-url
api             https://github.com/acme/api
frontend        https://github.com/acme/frontend
infra           git@github.com:acme/infra.git
```

Each project gets its own tmux window and its own session in the Claude app.
Leave the file empty to work in `/workspace` with a single session.

**3. Start**

```bash
docker compose up -d
```

**3. Get the SSH address from logs**

```bash
docker compose logs claude
```

```
╔══════════════════════════════════════════════════════╗
║           claude-danger-lab  is  ready!              ║
╠══════════════════════════════════════════════════════╣
║  Public:   ssh -p 2222 root@203.0.113.42             ║
║  Local:    ssh -p 2222 root@192.168.1.5              ║
║                                                      ║
║  After connecting:   tmux attach -t claude           ║
║  Detach:             Ctrl-a d                        ║
╚══════════════════════════════════════════════════════╝
```

**4. SSH in, attach to tmux, log in to claude.ai** *(first run only)*

```bash
ssh -p 2222 root@<address>
tmux attach -t claude
# inside Claude: type /login and follow the browser link
```

After login, Claude displays a session URL and QR code — open it from your phone and go.

On subsequent starts the session comes up automatically, no login needed.

---

## Daily use

| What | Command |
|------|---------|
| Start | `docker compose up -d` |
| See connection address | `docker compose logs claude` |
| Connect | `ssh -p 2222 root@<host>` |
| Attach to tmux | `tmux attach -t claude` |
| Switch between projects | `Ctrl-a w` |
| Detach (leave running) | `Ctrl-a d` |
| Stop | `docker compose down` |
| Update image | `docker compose pull && docker compose up -d` |

---

## Instructions

Claude Code reads `CLAUDE.md` files automatically. danger-lab maps them to files in the `instructions/` directory.

### Global instructions — `instructions/global.md`

Applied to **every** Claude session across all projects. Good for:

- Development workflow and process steps
- Cross-project coding standards
- Communication preferences

```markdown
# instructions/global.md

## Development workflow
1. Understand the task scope before touching anything.
2. Run existing tests first, fix failures before adding new code.
3. Commit with a message explaining *why*, not just *what*.
```

### Per-project instructions — `instructions/<name>.md`

`<name>` must match the session name in `projects.conf`. Applied to that project's `CLAUDE.md` **only if the repo doesn't already have one**.

```
instructions/
  global.md        ← all sessions
  api.md           ← project named "api" in projects.conf
  frontend.md      ← project named "frontend"
```

If the repo already has its own `CLAUDE.md` committed, it is left untouched (the repo's instructions win).

Changes to instruction files take effect on the next `docker compose restart`.

---

## Authentication

### Claude Code — required for remote control

Remote Control requires a **claude.ai account** (Pro, Max, Team, or Enterprise), not an API key. On first start, attach to the tmux session and log in:

```bash
tmux attach -t claude   # inside the container
# Claude will prompt: type /login and follow the browser link
```

Auth state is saved in a Docker volume — you only do this once.

After login, `claude remote-control` displays a session URL and QR code.
Open the URL or scan the code from the Claude mobile app to connect.

> **API key** (`ANTHROPIC_API_KEY` in `.env`) is still useful for other Claude Code
> operations but does not enable Remote Control.

### GitHub CLI

Run inside the container after connecting:

```bash
gh auth login
```

---

## SSH tips

Add to `~/.ssh/config` to skip typing the port every time:

```
Host danger-lab
    HostName <your-server-ip>
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
```

**Mobile:** Termius (iOS/Android) or Blink Shell (iOS) — port `2222`, user `root`, your private key.

---

## tmux reference

Prefix is `Ctrl-a`.

| Keys | Action |
|------|--------|
| `Ctrl-a d` | Detach — Claude keeps running |
| `Ctrl-a c` | New window |
| `Ctrl-a \|` | Split pane vertically |
| `Ctrl-a -` | Split pane horizontally |
| `Ctrl-a h/j/k/l` | Navigate panes |

Mouse is enabled.

---

## Troubleshooting

**No connection address in logs**

```bash
docker compose logs claude   # check for errors
docker compose ps            # check container is running
```

**SSH key rejected**

```bash
docker compose exec claude cat /root/.ssh/authorized_keys
```

**"Host key changed" warning** — happens after `docker compose down -v`:

```bash
ssh-keygen -R "[localhost]:2222"
```

**Claude not authenticated**

```bash
# Connect and run:
claude login
```

---

## What's inside

Ubuntu 22.04 · tmux · git · gh · curl · build-essential · Go (latest stable) · Node.js · Claude Code · OpenSSH

Persistent data:
- `/workspace` — your project files (host bind mount)
- `/root/.claude` — Claude memory and auth (named volume)
- `/etc/ssh/host-keys` — SSH host keys, stable fingerprint (named volume)

---

## License

MIT
