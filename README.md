# claude-danger-lab

[![Build](https://github.com/CheeryProgrammer/claude-danger-lab/actions/workflows/build.yml/badge.svg)](https://github.com/CheeryProgrammer/claude-danger-lab/actions/workflows/build.yml)

> **Disclaimer:** This project gives Claude Code broad, unsupervised access to your files, shell, and network inside the container. You take full responsibility for anything it does. The authors provide no warranty and accept no liability for data loss, security incidents, or any other damage. Use at your own risk.

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in an isolated Docker container. SSH in from anywhere, attach to tmux, and control Claude remotely — including from your phone via the Claude app.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/CheeryProgrammer/claude-danger-lab/main/install.sh | bash
```

Creates `claude-danger-lab/` with all required files and prints what to do next.

---

## First-time setup

**1. Fill in `.env`**

```bash
cd claude-danger-lab
$EDITOR .env
```

| Variable | What to put |
|----------|-------------|
| `SSH_PUBLIC_KEY` | Output of `cat ~/.ssh/id_ed25519.pub` |
| `ANTHROPIC_API_KEY` | From [console.anthropic.com](https://console.anthropic.com/) *(optional)* |
| `DANGEROUS_MODE` | `true` to skip all permission prompts, `false` to keep them |

**2. Add projects to `projects.conf`** *(optional)*

```
# name       git-url
api          https://github.com/you/api
frontend     https://github.com/you/frontend
```

Each project gets its own tmux window and its own session in the Claude app.
Leave the file empty to use a single session in `/workspace`.

**3. Start**

```bash
docker compose up -d
docker compose logs claude   # shows SSH address
```

**4. Log in to claude.ai** *(first run only — required for remote control)*

```bash
ssh -p 2222 root@<address>
tmux attach -t claude
# inside Claude: /login  → follow the browser link
```

After login, Claude shows a session URL and QR code. Open it on your phone — done.
Auth is saved in a volume and persists across restarts.

---

## Daily use

```bash
docker compose up -d                      # start
docker compose logs claude                # get SSH address
ssh -p 2222 root@<host>                   # connect
tmux attach -t claude                     # attach to Claude
# Ctrl-a w  — switch between projects
# Ctrl-a d  — detach (Claude keeps running)
docker compose down                       # stop
docker compose pull && docker compose up -d  # update
# build locally instead of pulling:
docker compose -f docker-compose.yml -f docker-compose.build.yml build && docker compose up -d
```

---

## Instructions for Claude

Claude reads `CLAUDE.md` files automatically. Place yours in `instructions/`:

| File | Scope |
|------|-------|
| `instructions/global.md` | All sessions, all projects |
| `instructions/<name>.md` | One project (name matches `projects.conf`) |

Per-project files are only applied if the repo doesn't already have its own `CLAUDE.md`.
Changes take effect after `docker compose restart`.

---

## SSH config shortcut

Add to `~/.ssh/config`:

```
Host danger-lab
    HostName <your-server-ip>
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
```

Then just `ssh danger-lab`. Mobile: Termius or Blink Shell, same settings.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No SSH address in logs | `docker compose ps` — is the container running? |
| SSH key rejected | `docker compose exec claude cat /root/.ssh/authorized_keys` |
| "Host key changed" | `ssh-keygen -R "[localhost]:2222"` — happens after `down -v` |
| Claude not logged in | Attach to tmux and run `/login` |

---

## What's inside

Ubuntu 22.04 · tmux · git · gh · Go (latest) · Node.js · Claude Code · OpenSSH

Persistent volumes: `claude-memory` (`~/.claude`) · `ssh-host-keys` (`/etc/ssh/host-keys`) · workspace (bind mount)

---

## License

MIT
