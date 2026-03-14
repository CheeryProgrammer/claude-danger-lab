# claude-danger-lab

An isolated, persistent runtime for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — safe-by-default infrastructure for dangerous-by-design AI-assisted development sessions.

**Intended workflow:**
```
docker compose up -d  →  SSH in  →  tmux attach  →  Claude Code  →  detach  →  reattach anytime (including from mobile)
```

---

## What's inside the container

| Tool | Purpose |
|------|---------|
| Ubuntu 22.04 | Base OS |
| tmux | Session manager — primary process owner |
| Claude Code | AI coding assistant |
| Go (latest stable) | Build toolchain |
| git | Version control |
| gh | GitHub CLI |
| curl / build-essential | General utilities |
| OpenSSH server | Remote access |

---

## Quick start

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/claude-danger-lab.git
cd claude-danger-lab
```

### 2. Configure the environment

```bash
cp .env.example .env
```

Edit `.env` and set at minimum:

| Variable | Description |
|----------|-------------|
| `SSH_PUBLIC_KEY` | Your SSH public key (required for SSH access) |
| `ANTHROPIC_API_KEY` | Your Anthropic API key (or authenticate inside later) |
| `WORKSPACE_PATH` | Host path to mount as `/workspace` (default: `./workspace`) |

Get your public key:
```bash
cat ~/.ssh/id_ed25519.pub   # or id_rsa.pub / id_ecdsa.pub
```

Get an Anthropic API key at <https://console.anthropic.com/>.

### 3. Build and start

```bash
docker compose up -d --build
```

The first build takes a few minutes (Go + Node.js + Claude Code install).

### 4. SSH into the container

```bash
ssh -p 2222 root@localhost
```

For a remote server, replace `localhost` with your server's IP or hostname.

On first connection you will be asked to accept the host fingerprint.
The fingerprint is stored in a Docker volume and will not change on subsequent restarts.

### 5. Attach to the Claude session

```bash
tmux attach -t claude
```

Claude Code is already running inside the session.

---

## Authentication

### Claude Code

**Method A — API key (recommended for unattended/automated use)**

Set `ANTHROPIC_API_KEY` in `.env` before starting the container.
Claude Code reads this environment variable automatically.

**Method B — Interactive login (OAuth / Claude.ai account)**

Leave `ANTHROPIC_API_KEY` empty, then inside the tmux session run:

```bash
claude login
```

Follow the prompts. Auth state is persisted in the `/root/.claude` volume
and survives container restarts and recreation.

### GitHub CLI

GitHub authentication is **not automatic**. To authenticate inside the container:

```bash
gh auth login
```

Follow the interactive prompts (device code flow works in headless environments).
The resulting token is stored in the container's home directory (which is
ephemeral — if you need it to persist, add `/root/.config` to a volume or
commit the token path explicitly).

---

## Daily workflow

### Start the environment

```bash
docker compose up -d
```

### SSH in

```bash
ssh -p 2222 root@<host>
```

A banner will remind you how to attach:

```
  ┌─────────────────────────────────────────────┐
  │  claude-danger-lab                          │
  │                                             │
  │  Attach to Claude session:                  │
  │    tmux attach -t claude                    │
  │                                             │
  │  List sessions:  tmux ls                    │
  │  Detach:         Ctrl-a d                   │
  └─────────────────────────────────────────────┘
```

### Attach to Claude

```bash
tmux attach -t claude
```

### Detach and leave Claude running

Press `Ctrl-a d` inside tmux.
Claude continues running in the background. You can close the SSH connection.

### Reattach later (including from mobile)

```bash
ssh -p 2222 root@<host>
tmux attach -t claude
```

### Stop the environment

```bash
docker compose down
```

Claude memory and SSH host keys are preserved in named volumes.
Your workspace on the host is unchanged.

### Destroy everything (including volumes)

```bash
docker compose down -v
```

---

## tmux key bindings

The prefix is **`Ctrl-a`** (not the default `Ctrl-b`).

| Key | Action |
|-----|--------|
| `Ctrl-a d` | Detach (leave session running) |
| `Ctrl-a c` | New window (opens in /workspace) |
| `Ctrl-a |` | Split pane horizontally |
| `Ctrl-a -` | Split pane vertically |
| `Ctrl-a h/j/k/l` | Navigate panes (vim-style) |
| `Ctrl-a D` | Choose session to detach/switch |
| `Ctrl-a r` | Reload tmux config |

Mouse support is enabled — you can click to select panes and scroll with the wheel.

---

## SSH configuration tips

### Persistent SSH alias (`~/.ssh/config` on your machine)

```
Host danger-lab
    HostName <your-server-ip>
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 10
```

Then connect with:
```bash
ssh danger-lab
```

### Mobile SSH clients

Recommended apps:
- **iOS**: Termius, Blink Shell, SSH Files
- **Android**: Termius, JuiceSSH

Configure the connection with port `2222`, user `root`, and your private key.

---

## Volumes

| Volume | Mount point | Purpose |
|--------|-------------|---------|
| `claude-memory` | `/root/.claude` | Claude Code state, session history, settings |
| `ssh-host-keys` | `/etc/ssh/host-keys` | SSH host keys (stable fingerprint) |
| `WORKSPACE_PATH` (bind mount) | `/workspace` | Your project files |

---

## Configuration reference

All configuration lives in `.env` (copy from `.env.example`):

```bash
SSH_PUBLIC_KEY=ssh-ed25519 AAAA...   # Required for SSH access
SSH_PORT=2222                         # Host port for SSH (default: 2222)
ANTHROPIC_API_KEY=sk-ant-...          # Optional; use `claude login` instead
WORKSPACE_PATH=./workspace            # Host path mounted to /workspace
MEMORY_LIMIT=4g                       # Container memory limit
```

### Updating Go version

```bash
# In .env or as a build arg:
docker compose build --build-arg GO_VERSION=1.24.2
docker compose up -d
```

### Changing the SSH port

```bash
SSH_PORT=2200 docker compose up -d
```

---

## Architecture

```
Host machine
│
├── docker compose up -d
│       └── claude-danger-lab container (Ubuntu 22.04)
│               ├── sshd  (PID 1, port 22 → host :2222)
│               └── tmux session "claude"
│                       └── claude (Claude Code CLI, foreground)
│
├── Host bind mount: WORKSPACE_PATH → /workspace
│
└── Docker named volumes:
        ├── claude-memory  → /root/.claude
        └── ssh-host-keys  → /etc/ssh/host-keys
```

**Process lifecycle:**
- `sshd` is the container's main process (PID 1 via `exec`).
- The tmux session is created at startup and owned by the root user.
- Claude Code runs inside tmux — detaching does not kill the process.
- Container restarts re-create the tmux session and re-launch Claude automatically.

---

## Security notes

- Root SSH login is allowed **only via public key** — password authentication is disabled.
- No ports other than SSH are exposed to the host.
- The container has access to your `WORKSPACE_PATH` and any credentials you inject via `.env`.
- This environment is intentionally permissive inside the container ("danger mode") — Claude Code can read, write, and execute anything within `/workspace`.
- Do not expose port 2222 publicly without a firewall rule limiting source IPs, or put it behind a VPN.

---

## Troubleshooting

**Cannot SSH — connection refused**
```bash
docker compose ps          # check container is running
docker compose logs claude # check for sshd errors
```

**SSH key rejected**
```bash
# Verify SSH_PUBLIC_KEY is set correctly in .env
docker compose exec claude cat /root/.ssh/authorized_keys
```

**Host key changed warning**
```bash
# This happens only after `docker compose down -v` (volumes destroyed).
ssh-keygen -R "[localhost]:2222"
# Then reconnect and accept the new fingerprint.
```

**tmux session not found**
```bash
# Check whether the container started cleanly
docker compose logs --tail=50 claude
# Manually create a session
docker compose exec claude tmux new-session -A -s claude
```

**Claude Code not authenticated**
```bash
# Inside the container (via ssh or docker exec):
claude login
# or set ANTHROPIC_API_KEY in .env and restart
```

**Out of memory**
```bash
# Increase MEMORY_LIMIT in .env:
MEMORY_LIMIT=8g
docker compose up -d
```

---

## License

MIT — use freely, break things responsibly.
