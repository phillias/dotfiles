#!/bin/bash
# install-hermes-honcho.sh — Manual installer for Hermes CLI + Honcho scheduler
# NOT auto-executed by chezmoi. Run explicitly: ./scripts/install-hermes-honcho.sh
#
# Prerequisites:
#   1. Run the audit steps on the live machine first to discover the actual
#      Hermes binary source and version.
#   2. Set environment variables or edit defaults below.
#
# Environment variables (with defaults):
#   HERMES_SOURCE       github-release | local-build  (default: github-release)
#   HERMES_GITHUB_OWNER                                  (default: your-org)
#   HERMES_GITHUB_REPO                                   (default: hermes)
#   HERMES_VERSION                                       (default: latest)
#   HERMES_LOCAL_REPO                                    (default: empty)
#   HONCHO_PIP_PACKAGE                                   (default: honcho)
#   HONCHO_VERSION                                       (default: latest)
#   MYBRAIN_REPO_URL                                     (default: git@github.com:phillias/mybrain.git)
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# Configuration (env vars with fallbacks)
# ═══════════════════════════════════════════════════════════════════

HERMES_SOURCE="${HERMES_SOURCE:-github-release}"
HERMES_GITHUB_OWNER="${HERMES_GITHUB_OWNER:-your-org}"
HERMES_GITHUB_REPO="${HERMES_GITHUB_REPO:-hermes}"
HERMES_VERSION="${HERMES_VERSION:-latest}"
HERMES_LOCAL_REPO="${HERMES_LOCAL_REPO:-}"

HONCHO_PIP_PACKAGE="${HONCHO_PIP_PACKAGE:-honcho}"
HONCHO_VERSION="${HONCHO_VERSION:-latest}"

MYBRAIN_REPO_URL="${MYBRAIN_REPO_URL:-git@github.com:phillias/mybrain.git}"
MYBRAIN_DIR="${MYBRAIN_HOME:-$HOME/mybrain}"

# Paths
INSTALL_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.local/share/hermes"
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$DATA_DIR/cron" "$DATA_DIR/cache/images" \
  "$DATA_DIR/cache/documents" "$DATA_DIR/cache/audio" "$DATA_DIR/logs"

# Detect OS/arch
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
esac

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     Hermes+Honcho Installer (manual)            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  OS:        $OS/$ARCH"
echo "  Hermes:    $HERMES_SOURCE ($HERMES_GITHUB_OWNER/$HERMES_GITHUB_REPO @ $HERMES_VERSION)"
echo "  Honcho:    $HONCHO_PIP_PACKAGE $HONCHO_VERSION"
echo "  Mybrain:   $MYBRAIN_DIR"
echo ""

# ═══════════════════════════════════════════════════════════════════
# 1. Install Hermes CLI
# ═══════════════════════════════════════════════════════════════════
install_hermes() {
  if command -v hermes &>/dev/null; then
    echo "  ✓ Hermes already installed: $(hermes version 2>/dev/null || echo 'ok')"
    return
  fi

  echo "  → Installing Hermes..."

  case "$HERMES_SOURCE" in
    github-release)
      local url="https://github.com/${HERMES_GITHUB_OWNER}/${HERMES_GITHUB_REPO}/releases/${HERMES_VERSION}/download/hermes_${OS}_${ARCH}.tar.gz"
      echo "    Downloading: $url"
      curl -fsSL "$url" -o /tmp/hermes.tar.gz \
        && tar -xzf /tmp/hermes.tar.gz -C "$INSTALL_DIR" hermes \
        && rm -f /tmp/hermes.tar.gz \
        || { echo "    Download failed. Install manually from $url"; exit 1; }
      ;;
    local-build)
      if [ -n "$HERMES_LOCAL_REPO" ] && [ -d "$HERMES_LOCAL_REPO" ]; then
        echo "    Building from: $HERMES_LOCAL_REPO"
        (cd "$HERMES_LOCAL_REPO" && go build -o "$INSTALL_DIR/hermes" .)
      else
        echo "    ERROR: HERMES_LOCAL_REPO not set or not found"
        exit 1
      fi
      ;;
    *)
      echo "    ERROR: Unknown HERMES_SOURCE: $HERMES_SOURCE"
      echo "    Set to 'github-release' or 'local-build' via env var."
      exit 1
      ;;
  esac

  chmod +x "$INSTALL_DIR/hermes"
  echo "  ✓ Hermes installed: $INSTALL_DIR/hermes"
}

# ═══════════════════════════════════════════════════════════════════
# 2. Install Honcho
# ═══════════════════════════════════════════════════════════════════
install_honcho() {
  if command -v honcho &>/dev/null; then
    echo "  ✓ Honcho already installed: $(honcho --version 2>/dev/null || echo 'ok')"
    return
  fi

  echo "  → Installing Honcho via pip..."
  local ver_flag="$HONCHO_PIP_PACKAGE"
  if [ "$HONCHO_VERSION" != "latest" ]; then
    ver_flag="${HONCHO_PIP_PACKAGE}==${HONCHO_VERSION}"
  fi

  if command -v pip3 &>/dev/null; then
    pip3 install --user "$ver_flag"
  elif command -v pip &>/dev/null; then
    pip install --user "$ver_flag"
  else
    echo "    ERROR: pip not found. Install Python/pip first."
    exit 1
  fi
  echo "  ✓ Honcho installed: $(honcho --version 2>/dev/null || echo 'ok')"
}

# ═══════════════════════════════════════════════════════════════════
# 3. Clone mybrain repo (if not present)
# ═══════════════════════════════════════════════════════════════════
setup_mybrain() {
  if [ -d "$MYBRAIN_DIR/.git" ]; then
    echo "  ✓ mybrain repo already cloned at $MYBRAIN_DIR"
    return
  fi

  echo "  → Cloning mybrain..."
  git clone "$MYBRAIN_REPO_URL" "$MYBRAIN_DIR"
  echo "  ✓ mybrain cloned to $MYBRAIN_DIR"
}

# ═══════════════════════════════════════════════════════════════════
# 4. Enable systemd user services
# ═══════════════════════════════════════════════════════════════════
setup_systemd() {
  echo "  → Reloading systemd user daemon..."
  systemctl --user daemon-reload

  for unit in hermes-cron hermes-honcho; do
    local tmr="${unit}.timer"

    if systemctl --user is-enabled "$tmr" &>/dev/null; then
      echo "    ✓ ${tmr} already enabled"
    else
      systemctl --user enable --now "$tmr"
      echo "    ✓ ${tmr} enabled and started"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════════
# 5. Register MCP servers
# ═══════════════════════════════════════════════════════════════════
register_mcp() {
  if ! command -v hermes &>/dev/null; then
    echo "  ⚠  hermes not on PATH — skipping MCP registration"
    return
  fi

  echo "  → Registering MCP servers..."

  if hermes mcp list 2>/dev/null | grep -q "mybrain-brain"; then
    echo "    ✓ mybrain-brain MCP already registered"
  elif [ -f "${MYBRAIN_DIR}/scripts/hermes/mybrain-mcp-server.py" ]; then
    hermes mcp add mybrain-brain \
      --command "python3" \
      --args "${MYBRAIN_DIR}/scripts/hermes/mybrain-mcp-server.py"
    echo "    ✓ mybrain-brain MCP registered"
  else
    echo "    ⚠  mybrain-mcp-server.py not found — skip MCP registration"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# 6. Verify
# ═══════════════════════════════════════════════════════════════════
verify() {
  local failed=0
  echo ""
  echo "  ── Verification ──"

  for cmd in hermes honcho; do
    if command -v "$cmd" &>/dev/null; then
      local ver
      ver="$($cmd version 2>/dev/null || $cmd --version 2>/dev/null || echo 'installed')"
      echo "    ✓ $cmd: $ver"
    else
      echo "    ✗ $cmd: NOT FOUND"
      failed=1
    fi
  done

  if [ -f "$MYBRAIN_DIR/scripts/hermes/mybrain-daily.sh" ]; then
    echo "    ✓ mybrain repo: $MYBRAIN_DIR"
  else
    echo "    ✗ mybrain repo: scripts/hermes/ missing"
    failed=1
  fi

  for timer in hermes-cron.timer hermes-honcho.timer; do
    if systemctl --user is-active "$timer" &>/dev/null; then
      echo "    ✓ $timer: active"
    else
      echo "    ✗ $timer: inactive"
      failed=1
    fi
  done

  if [ -f "$HOME/.hermes-env" ]; then
    echo "    ✓ .hermes-env: present"
  else
    echo "    ✗ .hermes-env: missing"
    failed=1
  fi

  if [ "$failed" -eq 0 ]; then
    echo ""
    echo "  ✓ All checks passed — Hermes+Honcho ready"
  else
    echo ""
    echo "  ⚠  Some checks failed — review above"
  fi
  return "$failed"
}

# ═══════════════════════════════════════════════════════════════════
# Execute
# ═══════════════════════════════════════════════════════════════════
install_hermes
install_honcho
setup_mybrain
setup_systemd
register_mcp
verify
