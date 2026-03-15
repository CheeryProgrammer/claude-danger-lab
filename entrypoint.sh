#!/usr/bin/env bash
# entrypoint.sh – container startup for claude-danger-lab
set -euo pipefail

log()  { echo "[danger-lab] $*"; }
warn() { echo "[danger-lab] WARN: $*" >&2; }

PROJECTS_CONF="/etc/danger-lab/projects.conf"
LAB_USER="lab"
LAB_HOME="/home/lab"

# Claude runs as $LAB_USER (non-root) so --permission-mode bypassPermissions works.
DANGEROUS="${DANGEROUS_MODE:-false}"
if [ "${DANGEROUS}" = "true" ]; then
    CLAUDE_CMD="claude remote-control --permission-mode bypassPermissions"
else
    CLAUDE_CMD="claude remote-control"
fi

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
    fi
}

# ── 2. SSH host keys ──────────────────────────────────────────────────────────
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

# ── 3. Environment file (secrets shared to lab user via /etc/danger-lab.env) ──
setup_env_file() {
    # Always recreate so key changes take effect on restart
    : > /etc/danger-lab.env
    chmod 640 /etc/danger-lab.env
    chgrp "${LAB_USER}" /etc/danger-lab.env

    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        printf 'export ANTHROPIC_API_KEY=%s\n' "${ANTHROPIC_API_KEY}" >> /etc/danger-lab.env
        log "ANTHROPIC_API_KEY set."
    fi

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        printf 'export GITHUB_TOKEN=%s\n' "${GITHUB_TOKEN}" >> /etc/danger-lab.env
        log "GITHUB_TOKEN set."
    fi
}

# ── 4. GitHub git config ──────────────────────────────────────────────────────
setup_github_auth() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        # Configure for both root and lab user
        for home in /root "${LAB_HOME}"; do
            git config --file "${home}/.gitconfig" \
                url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf \
                "https://github.com/"
        done
        chown "${LAB_USER}:${LAB_USER}" "${LAB_HOME}/.gitconfig" 2>/dev/null || true
    fi
}

# ── 5. Claude memory + global instructions ────────────────────────────────────
setup_claude_memory() {
    mkdir -p "${LAB_HOME}/.claude"
    chown -R "${LAB_USER}:${LAB_USER}" "${LAB_HOME}/.claude"

    local global_src="/etc/danger-lab/instructions/global.md"
    if [ -f "${global_src}" ]; then
        cp "${global_src}" "${LAB_HOME}/.claude/CLAUDE.md"
        chown "${LAB_USER}:${LAB_USER}" "${LAB_HOME}/.claude/CLAUDE.md"
        log "Global instructions loaded."
    fi

    # .claude.json lives outside the volume — restore from backup if missing
    local cfg="${LAB_HOME}/.claude.json"
    if [ ! -f "${cfg}" ]; then
        local latest
        latest=$(ls -t "${LAB_HOME}/.claude/backups/.claude.json.backup."* 2>/dev/null | head -1)
        if [ -n "${latest}" ]; then
            cp "${latest}" "${cfg}"
            chown "${LAB_USER}:${LAB_USER}" "${cfg}"
            log "Restored Claude config from backup."
        fi
    fi
}

# ── 6. Workspace ownership ────────────────────────────────────────────────────
setup_workspace() {
    mkdir -p /workspace
    chown "${LAB_USER}:${LAB_USER}" /workspace
}

# ── 7. Per-project instructions ───────────────────────────────────────────────
apply_project_instructions() {
    local name="$1"
    local src="/etc/danger-lab/instructions/${name}.md"
    local dst="/workspace/${name}/CLAUDE.md"
    [ -f "${src}" ] || return 0
    if [ -f "${dst}" ]; then
        log "[${name}] Repo already has CLAUDE.md — skipping."
    else
        cp "${src}" "${dst}"
        chown "${LAB_USER}:${LAB_USER}" "${dst}"
        log "[${name}] Project instructions applied."
    fi
}

# ── 8. Projects ───────────────────────────────────────────────────────────────
read_projects() {
    [ -f "${PROJECTS_CONF}" ] || return 0
    grep -v '^\s*#' "${PROJECTS_CONF}" | grep -v '^\s*$' || true
}

ensure_cloned() {
    local name="$1" url="$2"
    local dir="/workspace/${name}"
    if [ -d "${dir}/.git" ]; then
        log "[${name}] Already cloned."
        return 0
    fi
    log "[${name}] Cloning ${url}…"
    if sudo -u "${LAB_USER}" git clone "${url}" "${dir}"; then
        log "[${name}] Cloned OK."
    else
        warn "[${name}] git clone failed — skipping."
        return 1
    fi
}

# Run a command as lab user in a tmux window
tmux_run_as_lab() {
    local target="$1" dir="$2" cmd="$3"
    # Switch to lab user's login shell first, then run the command.
    # Two-step so the window stays as lab's shell if claude exits.
    tmux send-keys -t "${target}" "su - ${LAB_USER}" Enter
    sleep 0.5
    tmux send-keys -t "${target}" "cd ${dir} && ${cmd}" Enter
}

start_claude_window() {
    local session="$1" name="$2" dir="$3" first="$4"
    if [ "${first}" = "true" ]; then
        tmux rename-window -t "${session}:1" "${name}"
        tmux_run_as_lab "${session}:${name}" "${dir}" "${CLAUDE_CMD} --name '${name}'"
    else
        tmux new-window -t "${session}" -n "${name}"
        tmux_run_as_lab "${session}:${name}" "${dir}" "${CLAUDE_CMD} --name '${name}'"
    fi
    log "[${name}] Claude started."
}

# ── 9. tmux session ───────────────────────────────────────────────────────────
setup_tmux_session() {
    local session="claude"
    tmux new-session -d -s "${session}" -x 220 -y 50

    local projects
    projects=$(read_projects)

    if [ -z "${projects}" ]; then
        log "No projects configured — using /workspace."
        tmux rename-window -t "${session}:1" "claude"
        tmux_run_as_lab "${session}:claude" "/workspace" "${CLAUDE_CMD} --name 'danger-lab'"
        return
    fi

    local first=true
    while IFS= read -r line; do
        local name url
        name=$(awk '{print $1}' <<< "${line}")
        url=$(awk '{print $2}'  <<< "${line}")
        [ -z "${name}" ] || [ -z "${url}" ] && continue

        ensure_cloned "${name}" "${url}" || continue
        apply_project_instructions "${name}"
        start_claude_window "${session}" "${name}" "/workspace/${name}" "${first}"
        first=false
    done <<< "${projects}"

    if [ "${first}" = "true" ]; then
        warn "All clones failed — falling back to /workspace."
        tmux rename-window -t "${session}:1" "claude"
        tmux_run_as_lab "${session}:claude" "/workspace" "${CLAUDE_CMD} --name 'danger-lab'"
    fi
}

# ── 10. Connection banner ─────────────────────────────────────────────────────
print_connection_info() {
    local port="${SSH_PORT:-2222}"
    local public_ip
    public_ip=$(curl -fsSL --max-time 4 https://icanhazip.com 2>/dev/null | tr -d '[:space:]') || true
    local local_ip
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
    local projects
    projects=$(read_projects)
    local project_count
    project_count=$([ -n "${projects}" ] && wc -l <<< "${projects}" | tr -d ' ' || echo 1)

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║           claude-danger-lab  is  ready!              ║"
    echo "╠══════════════════════════════════════════════════════╣"
    [ -n "${public_ip}" ] && \
    echo "║  Public:   ssh -p ${port} root@${public_ip}"
    [ -n "${local_ip}" ] && \
    echo "║  Local:    ssh -p ${port} root@${local_ip}"
    echo "║                                                      ║"
    printf  "║  Projects: %-41s║\n" "${project_count} session(s) starting"
    echo "║  Attach:   tmux attach -t claude                     ║"
    echo "║  Windows:  Ctrl-a w  (switch between projects)       ║"
    echo "║  Detach:   Ctrl-a d                                  ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
}

# ── 11. Start SSH daemon ──────────────────────────────────────────────────────
start_sshd() {
    /usr/sbin/sshd -t || { warn "sshd config test failed"; exit 1; }
    exec /usr/sbin/sshd -D -e
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    log "Starting claude-danger-lab (Claude runs as user '${LAB_USER}')…"
    setup_ssh_auth
    setup_ssh_host_keys
    setup_env_file
    setup_github_auth
    setup_claude_memory
    setup_workspace
    setup_tmux_session
    print_connection_info
    start_sshd
}

main "$@"
