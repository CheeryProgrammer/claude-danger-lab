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

# Anthropic API key — get it at https://console.anthropic.com/
ANTHROPIC_API_KEY=sk-ant-...
```

**2. Start**

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
| Attach to Claude | `tmux attach -t claude` |
| Detach (leave running) | `Ctrl-a d` |
| Stop | `docker compose down` |
| Update image | `docker compose pull && docker compose up -d` |

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
