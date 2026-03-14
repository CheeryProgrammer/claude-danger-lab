# claude-danger-lab

[![Build](https://github.com/CheeryProgrammer/claude-danger-lab/actions/workflows/build.yml/badge.svg)](https://github.com/CheeryProgrammer/claude-danger-lab/actions/workflows/build.yml)

Isolated Docker container for running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in long-lived unattended sessions. Connect from anywhere — including mobile — over SSH, control Claude via tmux, detach and come back later.

---

## Setup (once)

**1. Clone and configure**

```bash
git clone https://github.com/CheeryProgrammer/claude-danger-lab.git
cd claude-danger-lab
cp .env.example .env
```

Open `.env` and fill in two values:

```bash
# Your SSH public key — get it with: cat ~/.ssh/id_ed25519.pub
SSH_PUBLIC_KEY=ssh-ed25519 AAAA...

# Your Anthropic API key — get it at https://console.anthropic.com/
ANTHROPIC_API_KEY=sk-ant-...
```

**2. Start**

```bash
docker compose up -d
```

That's it. Claude Code is now running inside the container.

---

## Daily use

**Connect and attach to Claude:**

```bash
ssh -p 2222 root@localhost        # or your server IP
tmux attach -t claude
```

**Leave Claude running, close the terminal:**

Press `Ctrl-a d` to detach from tmux. Claude keeps running. SSH session can be closed.

**Come back later:**

```bash
ssh -p 2222 root@localhost
tmux attach -t claude
```

**Stop everything:**

```bash
docker compose down               # data is preserved
docker compose down -v            # wipes volumes too
```

**Update to the latest image:**

```bash
docker compose pull && docker compose up -d
```

---

## Authentication

### Claude Code

**API key (recommended)** — set `ANTHROPIC_API_KEY` in `.env`, restart. Done.

**Interactive login** — leave `ANTHROPIC_API_KEY` empty, then inside the tmux session:

```bash
claude login
```

Auth state is saved in a Docker volume and survives restarts.

### GitHub CLI

Run inside the container after connecting:

```bash
gh auth login
```

---

## SSH tips

Add to `~/.ssh/config` on your machine to avoid typing the port every time:

```
Host danger-lab
    HostName localhost        # or your server IP
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
```

Then just: `ssh danger-lab`

**Mobile:** use Termius (iOS/Android) or Blink Shell (iOS). Port `2222`, user `root`, your private key.

---

## tmux quick reference

Prefix key is `Ctrl-a` (easier on mobile than the default `Ctrl-b`).

| Keys | Action |
|------|--------|
| `Ctrl-a d` | Detach — leave Claude running |
| `Ctrl-a c` | New window |
| `Ctrl-a \|` | Split pane vertically |
| `Ctrl-a -` | Split pane horizontally |
| `Ctrl-a h/j/k/l` | Navigate panes |

Mouse is enabled — click to focus, scroll with the wheel.

---

## Troubleshooting

**Can't SSH in**
```bash
docker compose ps                               # is the container running?
docker compose logs claude                      # any startup errors?
docker compose exec claude cat /root/.ssh/authorized_keys  # key loaded?
```

**"Host key changed" warning** — happens after `docker compose down -v`:
```bash
ssh-keygen -R "[localhost]:2222"
```

**tmux session missing**
```bash
docker compose exec claude tmux new-session -A -s claude
```

**Claude not authenticated**
```bash
# inside the container:
claude login
```

---

## What's inside

Ubuntu 22.04 · tmux · git · gh · curl · build-essential · Go · Node.js · Claude Code · OpenSSH server

Data that survives restarts:
- `/workspace` — your project files (bind mount from host)
- `/root/.claude` — Claude memory and auth state (named volume)
- `/etc/ssh/host-keys` — SSH host keys, so the fingerprint never changes (named volume)

---

## License

MIT
