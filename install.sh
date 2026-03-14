#!/usr/bin/env bash
# claude-danger-lab installer
# Usage: curl -fsSL https://raw.githubusercontent.com/CheeryProgrammer/claude-danger-lab/main/install.sh | bash
set -euo pipefail

REPO="CheeryProgrammer/claude-danger-lab"
RAW="https://raw.githubusercontent.com/${REPO}/main"
DIR="${CLAUDE_LAB_DIR:-claude-danger-lab}"

# ── Colours ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD='\033[1m'; GREEN='\033[32m'; CYAN='\033[36m'; RESET='\033[0m'
else
    BOLD=''; GREEN=''; CYAN=''; RESET=''
fi

log()  { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "${CYAN}→${RESET} $*"; }
bold() { echo -e "${BOLD}$*${RESET}"; }

# ── Checks ────────────────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    command -v docker  &>/dev/null || missing+=(docker)
    command -v curl    &>/dev/null || missing+=(curl)

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing required tools: ${missing[*]}"
        echo "Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker compose version &>/dev/null; then
        echo "Docker Compose plugin not found."
        echo "Install: https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# ── Download ──────────────────────────────────────────────────────────────────
fetch() {
    local path="$1"
    local dest="${DIR}/${path}"
    mkdir -p "$(dirname "${dest}")"
    curl -fsSL "${RAW}/${path}" -o "${dest}"
}

download_files() {
    info "Downloading into ./${DIR}/ …"

    fetch docker-compose.yml
    fetch projects.conf
    fetch .env.example
    fetch instructions/global.md
    fetch instructions/example-project.md

    log "Files downloaded."
}

# ── Setup ─────────────────────────────────────────────────────────────────────
setup_env() {
    if [ ! -f "${DIR}/.env" ]; then
        cp "${DIR}/.env.example" "${DIR}/.env"
        log ".env created from .env.example"
    else
        info ".env already exists — skipping."
    fi
}

# ── Next steps ────────────────────────────────────────────────────────────────
print_next_steps() {
    local pub_key=""
    for f in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
        if [ -f "$f" ]; then pub_key=$(cat "$f"); break; fi
    done

    echo ""
    bold "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bold " claude-danger-lab installed in ./${DIR}/"
    bold "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    bold "1. Edit .env"
    echo "   cd ${DIR} && \$EDITOR .env"
    echo ""

    if [ -n "${pub_key}" ]; then
        echo "   Your SSH public key (already pre-filled below — copy it in):"
        echo ""
        echo "   SSH_PUBLIC_KEY=${pub_key}"
    else
        echo "   SSH_PUBLIC_KEY=  ← paste output of: cat ~/.ssh/id_ed25519.pub"
    fi
    echo "   ANTHROPIC_API_KEY= ← from https://console.anthropic.com/"
    echo "   DANGEROUS_MODE=false"
    echo ""
    bold "2. (Optional) Add projects to projects.conf"
    echo "   # name    git-url"
    echo "   api       https://github.com/you/api"
    echo "   frontend  https://github.com/you/frontend"
    echo ""
    bold "3. Start"
    echo "   docker compose up -d"
    echo ""
    bold "4. Get SSH address"
    echo "   docker compose logs claude"
    echo ""
    bold "5. Connect and log in to claude.ai (first run only)"
    echo "   ssh -p 2222 root@<address>"
    echo "   tmux attach -t claude"
    echo "   # inside Claude: /login"
    echo ""
    echo "   After login, Claude shows a URL/QR code — open it on your phone."
    echo ""
    bold "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    bold "claude-danger-lab installer"
    echo ""

    check_deps
    download_files
    setup_env
    print_next_steps
}

main "$@"
