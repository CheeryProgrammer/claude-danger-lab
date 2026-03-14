#!/usr/bin/env bash
# entrypoint.sh – container startup for claude-danger-lab
set -euo pipefail

# ── Logging helpers ────────────────────────────────────────────────────────────
log()  { echo "[danger-lab] $*"; }
warn() { echo "[danger-lab] WARN: $*" >&2; }

# ── 1. SSH authorised keys ─────────────────────────────────────────────────────
setup_ssh_auth() {
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    local auth_file="/root/.ssh/authorized_keys"

    if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
        # Avoid duplicate entries on container restart
        if ! grep -qF "${SSH_PUBLIC_KEY}" "${auth_file}" 2>/dev/null; then
            echo "${SSH_PUBLIC_KEY}" >> "${auth_file}"
            log "SSH public key added from SSH_PUBLIC_KEY env var."
        fi
        chmod 600 "${auth_file}"
    else
        warn "SSH_PUBLIC_KEY is not set."
        warn "You will not be able to SSH into the container."
        warn "Set SSH_PUBLIC_KEY in .env or docker-compose.yml and restart."
    fi
}

# ── 2. SSH host keys ──────────────────────────────────────────────────────────
# Keys are stored in a named volume so the fingerprint survives container
# recreation.  Users only need to accept the fingerprint once.
setup_ssh_host_keys() {
    local key_dir="/etc/ssh/host-keys"
    mkdir -p "${key_dir}"

    if [ ! -f "${key_dir}/ssh_host_ed25519_key" ]; then
        log "Generating SSH host keys (first run)…"
        ssh-keygen -t ed25519 -f "${key_dir}/ssh_host_ed25519_key" -N "" -q
    fi

    if [ ! -f "${key_dir}/ssh_host_rsa_key" ]; then
        ssh-keygen -t rsa -b 4096 -f "${key_dir}/ssh_host_rsa_key" -N "" -q
    fi

    chmod 600 "${key_dir}"/ssh_host_*_key
    chmod 644 "${key_dir}"/ssh_host_*_key.pub
    log "SSH host keys ready."
}

# ── 3. Claude authentication ──────────────────────────────────────────────────
setup_claude_auth() {
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        log "ANTHROPIC_API_KEY detected – Claude will authenticate via API key."
        # Export so the tmux session inherits it
        export ANTHROPIC_API_KEY
        # Write to a dedicated env file so all future shells have access:
        # new tmux windows, docker exec sessions, etc.
        # Always overwrite so a key change in .env takes effect on restart.
        local env_file="/etc/danger-lab.env"
        printf 'export ANTHROPIC_API_KEY=%s\n' "${ANTHROPIC_API_KEY}" > "${env_file}"
        chmod 600 "${env_file}"
        # Hook the env file into every interactive shell via bashrc_extra
        # (the Dockerfile already sources /etc/bash.bashrc.d/*.sh)
        local rc_hook="/etc/bash.bashrc.d/claude-auth.sh"
        if [ ! -f "${rc_hook}" ]; then
            printf '# Injected by entrypoint at first start\n. /etc/danger-lab.env\n' \
                > "${rc_hook}"
        fi
    else
        warn "ANTHROPIC_API_KEY is not set."
        warn "Claude Code will start in unauthenticated mode."
        warn "Run 'claude login' inside the tmux session to authenticate."
    fi
}

# ── 4. Claude memory directory ────────────────────────────────────────────────
setup_claude_memory() {
    # /root/.claude is expected to be a named volume mount.
    # Create the directory in case the volume is empty on first run.
    mkdir -p /root/.claude
    log "Claude memory directory: /root/.claude"
}

# ── 5. tmux session ───────────────────────────────────────────────────────────
setup_tmux_session() {
    local session="claude"

    if tmux has-session -t "${session}" 2>/dev/null; then
        log "tmux session '${session}' already exists – skipping creation."
        return
    fi

    log "Creating tmux session '${session}'…"

    # Create a detached session sized for a typical terminal
    tmux new-session -d -s "${session}" -x 220 -y 50

    # Ensure we start in the workspace
    tmux send-keys -t "${session}" "cd /workspace" Enter

    # Launch Claude Code
    tmux send-keys -t "${session}" "claude" Enter

    log "Claude Code launched inside tmux session '${session}'."
    log "Attach with:  tmux attach -t ${session}"
}

# ── 6. Start SSH daemon ───────────────────────────────────────────────────────
start_sshd() {
    log "Starting SSH daemon…"
    # Test configuration before launching
    /usr/sbin/sshd -t \
        || { warn "sshd config test failed – check /etc/ssh/sshd_config"; exit 1; }
    # exec replaces this shell as PID 1; sshd manages its own child processes
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
    start_sshd
}

main "$@"
