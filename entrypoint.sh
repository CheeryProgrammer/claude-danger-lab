#!/usr/bin/env bash
# entrypoint.sh – container startup for claude-danger-lab
set -euo pipefail

log()  { echo "[danger-lab] $*"; }
warn() { echo "[danger-lab] WARN: $*" >&2; }

# ── 1. SSH authorised keys ────────────────────────────────────────────────────
setup_ssh_auth() {
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    local auth_file="/root/.ssh/authorized_keys"

    if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
        if ! grep -qF "${SSH_PUBLIC_KEY}" "${auth_file}" 2>/dev/null; then
            echo "${SSH_PUBLIC_KEY}" >> "${auth_file}"
        fi
        chmod 600 "${auth_file}"
    else
        warn "SSH_PUBLIC_KEY is not set — SSH login will be impossible."
        warn "Set SSH_PUBLIC_KEY in .env and restart."
    fi
}

# ── 2. SSH host keys ──────────────────────────────────────────────────────────
# Stored in a named volume — fingerprint survives container recreation.
setup_ssh_host_keys() {
    local key_dir="/etc/ssh/host-keys"
    mkdir -p "${key_dir}"

    if [ ! -f "${key_dir}/ssh_host_ed25519_key" ]; then
        log "Generating SSH host keys (first run)…"
        ssh-keygen -t ed25519 -f "${key_dir}/ssh_host_ed25519_key" -N "" -q
        ssh-keygen -t rsa    -b 4096 -f "${key_dir}/ssh_host_rsa_key"     -N "" -q
    fi

    chmod 600 "${key_dir}"/ssh_host_*_key
    chmod 644 "${key_dir}"/ssh_host_*_key.pub
}

# ── 3. Claude authentication ──────────────────────────────────────────────────
setup_claude_auth() {
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        export ANTHROPIC_API_KEY
        # Persist so new tmux windows and docker exec sessions also have it.
        printf 'export ANTHROPIC_API_KEY=%s\n' "${ANTHROPIC_API_KEY}" \
            > /etc/danger-lab.env
        chmod 600 /etc/danger-lab.env
        # Source it in every interactive shell.
        if [ ! -f /etc/bash.bashrc.d/claude-auth.sh ]; then
            printf '. /etc/danger-lab.env\n' > /etc/bash.bashrc.d/claude-auth.sh
        fi
    else
        warn "ANTHROPIC_API_KEY is not set."
        warn "Claude will start unauthenticated — run 'claude login' inside tmux."
    fi
}

# ── 4. Claude memory directory ────────────────────────────────────────────────
setup_claude_memory() {
    mkdir -p /root/.claude
}

# ── 5. tmux session with Claude in dangerous mode ────────────────────────────
setup_tmux_session() {
    local session="claude"

    if tmux has-session -t "${session}" 2>/dev/null; then
        log "tmux session '${session}' already exists."
        return
    fi

    tmux new-session -d -s "${session}" -x 220 -y 50
    tmux send-keys -t "${session}" "cd /workspace" Enter
    # remote-control: server mode — accepts connections from claude.ai and mobile app
    # --dangerously-skip-permissions: no approval prompts, full autonomy
    # Note: remote-control requires claude.ai login (not API key). If not yet
    # authenticated, attach to this session and run: claude login
    tmux send-keys -t "${session}" \
        "claude --dangerously-skip-permissions remote-control --name 'danger-lab'" Enter
    log "Claude Code started in remote-control server mode (tmux session '${session}')."
}

# ── 6. Connection banner ──────────────────────────────────────────────────────
print_connection_info() {
    local port="${SSH_PORT:-2222}"

    # Detect IPs
    local public_ip
    public_ip=$(curl -fsSL --max-time 4 https://icanhazip.com 2>/dev/null | tr -d '[:space:]') || true

    local local_ip
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║           claude-danger-lab  is  ready!              ║"
    echo "╠══════════════════════════════════════════════════════╣"
    if [ -n "${public_ip}" ]; then
    echo "║  Public:   ssh -p ${port} root@${public_ip}"
    fi
    if [ -n "${local_ip}" ]; then
    echo "║  Local:    ssh -p ${port} root@${local_ip}"
    fi
    echo "║                                                      ║"
    echo "║  After connecting:   tmux attach -t claude           ║"
    echo "║  Detach:             Ctrl-a d                        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

# ── 7. Start SSH daemon ───────────────────────────────────────────────────────
start_sshd() {
    /usr/sbin/sshd -t \
        || { warn "sshd config test failed"; exit 1; }
    exec /usr/sbin/sshd -D -e
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    log "Starting claude-danger-lab…"
    setup_ssh_auth
    setup_ssh_host_keys
    setup_claude_auth
    setup_claude_memory
    setup_tmux_session
    print_connection_info
    start_sshd
}

main "$@"
