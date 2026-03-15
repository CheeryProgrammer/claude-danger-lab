#!/usr/bin/env bash
# entrypoint.sh – container startup for claude-danger-lab
set -euo pipefail

log()  { echo "[danger-lab] $*"; }
warn() { echo "[danger-lab] WARN: $*" >&2; }

PROJECTS_CONF="/etc/danger-lab/projects.conf"
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
        warn "Set SSH_PUBLIC_KEY in .env and restart."
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

# ── 3. GitHub authentication ─────────────────────────────────────────────────
setup_github_auth() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        export GITHUB_TOKEN
        # Configure git to use the token for all github.com HTTPS operations
        git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
        # Persist for interactive shells
        printf 'export GITHUB_TOKEN=%s\n' "${GITHUB_TOKEN}" >> /etc/danger-lab.env
        log "GitHub token configured for git and gh CLI."
    fi
}

# ── 4. Claude auth env ────────────────────────────────────────────────────────
setup_claude_auth() {
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        export ANTHROPIC_API_KEY
        printf 'export ANTHROPIC_API_KEY=%s\n' "${ANTHROPIC_API_KEY}" \
            > /etc/danger-lab.env
        chmod 600 /etc/danger-lab.env
        if [ ! -f /etc/bash.bashrc.d/claude-auth.sh ]; then
            printf '. /etc/danger-lab.env\n' > /etc/bash.bashrc.d/claude-auth.sh
        fi
    fi
    # Note: claude remote-control requires claude.ai login, not API key.
    # On first run, attach to the tmux session and type: /login
}

# ── 4. Claude memory directory + global instructions ─────────────────────────
setup_claude_memory() {
    mkdir -p /root/.claude

    # Global instructions → ~/.claude/CLAUDE.md
    # Loaded by every Claude session across all projects.
    local global_src="/etc/danger-lab/instructions/global.md"
    if [ -f "${global_src}" ]; then
        cp "${global_src}" /root/.claude/CLAUDE.md
        log "Global instructions loaded from instructions/global.md"
    fi
}

# ── 5a. Per-project instructions ──────────────────────────────────────────────
# If instructions/<name>.md exists and the project has no CLAUDE.md yet,
# copy it in.  If the repo already has its own CLAUDE.md, don't overwrite it.
apply_project_instructions() {
    local name="$1"
    local project_dir="/workspace/${name}"
    local src="/etc/danger-lab/instructions/${name}.md"
    local dst="${project_dir}/CLAUDE.md"

    [ -f "${src}" ] || return 0   # no per-project file, nothing to do

    if [ -f "${dst}" ]; then
        log "[${name}] Repo already has CLAUDE.md — skipping instructions/${name}.md"
    else
        cp "${src}" "${dst}"
        log "[${name}] Project instructions applied from instructions/${name}.md"
    fi
}

# ── 5. Projects ───────────────────────────────────────────────────────────────
# Reads PROJECTS_CONF and returns a list of "name url" pairs (one per line),
# skipping comments and blank lines.
read_projects() {
    [ -f "${PROJECTS_CONF}" ] || return 0
    grep -v '^\s*#' "${PROJECTS_CONF}" | grep -v '^\s*$' || true
}

# Clone a project if not already present.
ensure_cloned() {
    local name="$1" url="$2"
    local dir="/workspace/${name}"

    if [ -d "${dir}/.git" ]; then
        log "[${name}] Already cloned."
        return 0
    fi

    log "[${name}] Cloning ${url}…"
    if git clone "${url}" "${dir}"; then
        log "[${name}] Cloned OK."
    else
        warn "[${name}] git clone failed — skipping."
        return 1
    fi
}

# Start Claude remote-control in a tmux window for one project.
start_claude_window() {
    local session="$1" name="$2" dir="$3" first="$4"

    if [ "${first}" = "true" ]; then
        # Rename the initial window that tmux created automatically.
        tmux rename-window -t "${session}:1" "${name}"
        tmux send-keys -t "${session}:${name}" "cd ${dir}" Enter
        tmux send-keys -t "${session}:${name}" \
            "${CLAUDE_CMD} --name '${name}'" Enter
    else
        tmux new-window -t "${session}" -n "${name}"
        tmux send-keys -t "${session}:${name}" "cd ${dir}" Enter
        tmux send-keys -t "${session}:${name}" \
            "${CLAUDE_CMD} --name '${name}'" Enter
    fi

    log "[${name}] Claude remote-control started."
}

# ── 6. tmux session ───────────────────────────────────────────────────────────
setup_tmux_session() {
    local session="claude"

    tmux new-session -d -s "${session}" -x 220 -y 50

    local projects
    projects=$(read_projects)

    if [ -z "${projects}" ]; then
        # No projects configured — single session in /workspace.
        log "No projects in projects.conf — using /workspace."
        tmux rename-window -t "${session}:1" "claude"
        tmux send-keys -t "${session}:claude" "cd /workspace" Enter
        tmux send-keys -t "${session}:claude" \
            "${CLAUDE_CMD} --name 'danger-lab'" Enter
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

    # If every clone failed, fall back to /workspace.
    if [ "${first}" = "true" ]; then
        warn "All project clones failed — falling back to /workspace."
        tmux rename-window -t "${session}:1" "claude"
        tmux send-keys -t "${session}:claude" "cd /workspace" Enter
        tmux send-keys -t "${session}:claude" \
            "${CLAUDE_CMD} --name 'danger-lab'" Enter
    fi
}

# ── 7. Connection banner ──────────────────────────────────────────────────────
print_connection_info() {
    local port="${SSH_PORT:-2222}"

    local public_ip
    public_ip=$(curl -fsSL --max-time 4 https://icanhazip.com 2>/dev/null \
        | tr -d '[:space:]') || true

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

# ── 8. Start SSH daemon ───────────────────────────────────────────────────────
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
    setup_github_auth
    setup_claude_auth
    setup_claude_memory
    setup_tmux_session
    print_connection_info
    start_sshd
}

main "$@"
