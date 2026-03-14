FROM ubuntu:22.04

# ── Build args ────────────────────────────────────────────────────────────────
# GO_VERSION: pin a specific release (e.g. 1.24.2) or leave as "latest" to
# auto-detect the current stable release from go.dev at build time.
ARG GO_VERSION=latest
ARG NODE_MAJOR=20
ARG DEBIAN_FRONTEND=noninteractive

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        tmux \
        git \
        curl \
        wget \
        gnupg \
        ca-certificates \
        lsb-release \
        build-essential \
        openssh-server \
        locales \
        postgresql-client \
        jq \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ── GitHub CLI ────────────────────────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
        https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js (required by Claude Code) ────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] \
        https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Go ────────────────────────────────────────────────────────────────────────
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "${GO_VERSION}" = "latest" ]; then \
         GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1 | sed 's/go//'); \
       fi \
    && echo "Installing Go ${GO_VERSION}" \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" \
    && tar -C /usr/local -xzf "go${GO_VERSION}.linux-${ARCH}.tar.gz" \
    && rm "go${GO_VERSION}.linux-${ARCH}.tar.gz"

ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
ENV GOPATH="/root/go"
# auto: use toolchain version from go.mod if it differs from the installed one
ENV GOTOOLCHAIN=auto

# ── Go tools ─────────────────────────────────────────────────────────────────
# goimports: import formatter
RUN go install golang.org/x/tools/cmd/goimports@latest

# golangci-lint: linter aggregator (latest version via official installer)
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
    | sh -s -- -b /usr/local/bin

# sqlc: SQL → Go code generator (latest release)
RUN ARCH=$(dpkg --print-architecture | sed 's/amd64/amd64/;s/arm64/arm64/') \
    && SQLC_VERSION=$(curl -fsSL https://api.github.com/repos/sqlc-dev/sqlc/releases/latest \
        | jq -r '.tag_name' | sed 's/v//') \
    && curl -fsSL "https://github.com/sqlc-dev/sqlc/releases/download/v${SQLC_VERSION}/sqlc_${SQLC_VERSION}_linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin sqlc

# golang-migrate: database migrations CLI (latest release, postgres + file support)
RUN ARCH=$(dpkg --print-architecture | sed 's/amd64/amd64/;s/arm64/arm64/') \
    && MIG_VERSION=$(curl -fsSL https://api.github.com/repos/golang-migrate/migrate/releases/latest \
        | jq -r '.tag_name' | sed 's/v//') \
    && curl -fsSL "https://github.com/golang-migrate/migrate/releases/download/v${MIG_VERSION}/migrate.linux-${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin migrate

# ── Claude Code ───────────────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code

# ── SSH configuration ─────────────────────────────────────────────────────────
RUN mkdir -p /var/run/sshd /etc/ssh/host-keys /root/.ssh \
    && chmod 700 /root/.ssh

COPY config/sshd_config /etc/ssh/sshd_config

# ── tmux configuration ────────────────────────────────────────────────────────
COPY config/tmux.conf /root/.tmux.conf

# ── Shell environment ─────────────────────────────────────────────────────────
COPY config/bashrc_extra /etc/bash.bashrc.d/danger-lab.sh
RUN echo 'if [ -d /etc/bash.bashrc.d ]; then' >> /root/.bashrc \
    && echo '  for f in /etc/bash.bashrc.d/*.sh; do . "$f"; done' >> /root/.bashrc \
    && echo 'fi' >> /root/.bashrc

# ── Workspace ─────────────────────────────────────────────────────────────────
RUN mkdir -p /workspace

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
