#!/usr/bin/env bash
# scripts/setup-omp.sh — Install oh-my-pi (omp) with DAP debugger support
# Usage: bash scripts/setup-omp.sh
#
# Installs:
#   - oh-my-pi (omp) coding agent via bun or prebuilt binary
#   - DAP debuggers: lldb-dap (C/C++), debugpy (Python), dlv (Go)
#   - Shell env additions (PATH, LD_LIBRARY_PATH)
#
# Run this AFTER chezmoi apply has placed ~/.omp/agent/ configs.

set -euo pipefail

INSTALL_DIR="${PI_INSTALL_DIR:-$HOME/.local/bin}"
MIN_BUN_VERSION="1.3.14"
IS_MAC=false
[ "$(uname -s)" = "Darwin" ] && IS_MAC=true

echo "=== oh-my-pi + DAP setup ($(hostname) - $(uname -sm)) ==="

# ─────────────────────────────────────────────────
# Phase 1 — Ensure ~/.local/bin exists and is on PATH
# ─────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

PATH_EXPORT='export PATH="$HOME/.local/bin:$PATH"'
LD_LIBRARY_EXPORT='export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"'

for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$shell_rc" ] || continue
    if ! grep -q '$HOME/.local/bin' "$shell_rc" 2>/dev/null; then
        echo "$PATH_EXPORT" >> "$shell_rc"
        echo "  => PATH updated in $(basename "$shell_rc")"
    fi
    if ! grep -q 'LD_LIBRARY_PATH.*local/lib' "$shell_rc" 2>/dev/null; then
        echo "$LD_LIBRARY_EXPORT" >> "$shell_rc"
        echo "  => LD_LIBRARY_PATH updated in $(basename "$shell_rc")"
    fi
done

export PATH="$HOME/.local/bin:$PATH"

# ─────────────────────────────────────────────────
# Phase 2 — Install/update bun
# ─────────────────────────────────────────────────
install_bun() {
    echo "==> Installing bun..."
    if command -v bash &>/dev/null; then
        curl -fsSL https://bun.sh/install | bash
    else
        curl -fsSL https://bun.sh/install | sh
    fi
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
}

has_bun() {
    command -v bun &>/dev/null || [ -x "$HOME/.bun/bin/bun" ]
}

bun_version_ok() {
    local ver
    ver=$(bun --version 2>/dev/null || true)
    [ -z "$ver" ] && return 1
    # Compare major.minor.patch as integer
    local ver_int maj min patch
    maj=$(echo "$ver" | cut -d. -f1)
    min=$(echo "$ver" | cut -d. -f2)
    patch=$(echo "$ver" | cut -d. -f3 | cut -d- -f1)
    ver_int=$((maj * 1000000 + min * 1000 + patch))
    local min_int
    maj=$(echo "$MIN_BUN_VERSION" | cut -d. -f1)
    min=$(echo "$MIN_BUN_VERSION" | cut -d. -f2)
    patch=$(echo "$MIN_BUN_VERSION" | cut -d. -f3)
    min_int=$((maj * 1000000 + min * 1000 + patch))
    [ "$ver_int" -ge "$min_int" ]
}

if has_bun; then
    if bun_version_ok; then
        echo "bun: $(bun --version) (OK)"
    else
        echo "bun: $(bun --version) — too old, upgrading..."
        curl -fsSL https://bun.sh/install | bash
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
        echo "bun: $(bun --version)"
    fi
else
    install_bun
fi

# Ensure .bun/bin is in PATH (for future shells)
for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$shell_rc" ] || continue
    if ! grep -q '\.bun/bin' "$shell_rc" 2>/dev/null; then
        echo 'export PATH="$HOME/.bun/bin:$PATH"' >> "$shell_rc"
    fi
done

# ─────────────────────────────────────────────────
# Phase 3 — Install/update oh-my-pi
# ─────────────────────────────────────────────────
echo ""
echo "==> Installing oh-my-pi..."

if command -v omp &>/dev/null; then
    echo "  omp already installed: $(omp --version 2>/dev/null || true)"
    echo "  Updating..."
    bun install -g @oh-my-pi/pi-coding-agent 2>/dev/null || true
else
    # Try bun first, fall back to prebuilt binary
    if command -v bun &>/dev/null; then
        bun install -g @oh-my-pi/pi-coding-agent || {
            echo "  bun install failed, trying prebuilt binary..."
            curl -fsSL https://omp.sh/install | sh -s -- --binary
        }
    else
        curl -fsSL https://omp.sh/install | sh -s -- --binary
    fi
fi

if command -v omp &>/dev/null; then
    echo "  omp: $(omp --version 2>/dev/null)"
else
    echo "  ERROR: omp install failed"
    exit 1
fi

# ─────────────────────────────────────────────────
# Phase 4 — Install DAP debuggers
# ─────────────────────────────────────────────────
echo ""
echo "==> Installing DAP debuggers..."

LLDB_DIR="$HOME/.local/lib/omp-lldb"
PYTHON=$(command -v python3 || command -v python || echo "")

# ── 4a. lldb-dap (C/C++) ────────────────────────
install_lldb_dap() {
    mkdir -p "$LLDB_DIR"

    if $IS_MAC; then
        if ! command -v lldb-dap &>/dev/null; then
            echo "  lldb-dap: installing via brew..."
            brew install llvm 2>/dev/null || true
            # llvm bottle includes lldb-dap
            if [ -x "/opt/homebrew/opt/llvm/bin/lldb-dap" ]; then
                ln -sf "/opt/homebrew/opt/llvm/bin/lldb-dap" "$INSTALL_DIR/lldb-dap"
            fi
        fi
    else
        # Linux: download lldb-* .debs and extract locally
        if command -v lldb-dap &>/dev/null; then
            echo "  lldb-dap: already in PATH"
            return
        fi

        # Determine distro version for package selection
        local distro_version
        distro_version=$( (grep VERSION_CODENAME /etc/os-release 2>/dev/null || echo "trixie") | cut -d= -f2)
        local llvm_version="19"
        local lldb_deb="lldb-${llvm_version}"
        local liblldb_deb="liblldb-${llvm_version}"

        # Check if system packages are available (root install)
        if command -v dpkg &>/dev/null && command -v sudo &>/dev/null; then
            if dpkg -l "$lldb_deb" &>/dev/null 2>&1; then
                # Find where lldb-dap was installed
                local lldb_bin
                lldb_bin=$(find /usr/lib/llvm-${llvm_version}/bin /usr/bin -name "lldb-dap*" -type f 2>/dev/null | head -1)
                if [ -n "$lldb_bin" ]; then
                    ln -sf "$lldb_bin" "$INSTALL_DIR/lldb-dap"
                    echo "  lldb-dap: using system package"
                    return
                fi
            fi
        fi

        # Download and extract .debs locally
        local tmp_dir
        tmp_dir=$(mktemp -d)
        echo "  lldb-dap: downloading packages (${lldb_deb} + ${liblldb_deb})..."

        if command -v apt-get &>/dev/null; then
            # Try apt-get download first (uses system sources)
            (cd "$tmp_dir" && apt-get download "$liblldb_deb" "$lldb_deb" 2>/dev/null) || {
                # Fallback: direct GitHub release binary
                echo "  lldb-dap: apt download failed, trying prebuilt binary..."
                local llvm_tag="llvmorg-${llvm_version}.1.7"
                curl -fsSL -o "$INSTALL_DIR/lldb-dap" \
                    "https://github.com/llvm/llvm-project/releases/download/${llvm_tag}/clang+llvm-${llvm_version}.1.7-x86_64-linux-gnu-ubuntu-24.04.tar.xz" 2>/dev/null && {
                    echo "  lldb-dap: downloaded prebuilt binary"
                } || {
                    echo "  WARN: lldb-dap download failed. Install manually."
                    rm -rf "$tmp_dir"
                    return
                }
            }

            # Extract .debs
            for deb in "$tmp_dir"/*.deb; do
                [ -f "$deb" ] && dpkg -x "$deb" "$LLDB_DIR" 2>/dev/null || true
            done

            # Find lldb-dap binary in extracted files
            local lldb_bin
            lldb_bin=$(find "$LLDB_DIR" -name "lldb-dap" -type f 2>/dev/null | head -1)
            if [ -n "$lldb_bin" ]; then
                ln -sf "$lldb_bin" "$INSTALL_DIR/lldb-dap"
                echo "  lldb-dap: installed ($(file "$lldb_bin" | awk '{print $2}'))"
            fi

            # Copy shared libraries to ~/.local/lib/
            find "$LLDB_DIR" -name "liblldb*.so*" -type f 2>/dev/null | while read -r lib; do
                cp -n "$lib" "$HOME/.local/lib/" 2>/dev/null || true
            done
        fi

        rm -rf "$tmp_dir"

        # Verify with ldd
        if [ -x "$INSTALL_DIR/lldb-dap" ]; then
            local missing
            missing=$(LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH" ldd "$INSTALL_DIR/lldb-dap" 2>/dev/null | grep "not found" || true)
            if [ -n "$missing" ]; then
                echo "  lldb-dap: warning — missing libraries:"
                echo "$missing" | sed 's/^/    /'
            else
                echo "  lldb-dap: all libraries resolved"
            fi
        fi
    fi
}

# ── 4b. debugpy (Python) ────────────────────────
install_debugpy() {
    if [ -z "$PYTHON" ]; then
        echo "  debugpy: python not found, skipping"
        return
    fi

    if python3 -c "import debugpy; print(debugpy.__version__)" 2>/dev/null; then
        echo "  debugpy: already installed"
    else
        echo "  debugpy: installing..."
        if command -v pip3 &>/dev/null; then
            pip3 install debugpy --break-system-packages 2>/dev/null || \
            pip3 install debugpy --user 2>/dev/null || \
            pip3 install debugpy 2>/dev/null || true
        elif command -v pip &>/dev/null; then
            pip install debugpy --break-system-packages 2>/dev/null || \
            pip install debugpy --user 2>/dev/null || true
        fi
        if python3 -c "import debugpy; print(debugpy.__version__)" 2>/dev/null; then
            echo "  debugpy: $(python3 -c "import debugpy; print(debugpy.__version__)")"
        else
            echo "  debugpy: install failed (pip not available)"
        fi
    fi
}

# ── 4c. dlv (Go) ────────────────────────────────
install_dlv() {
    if command -v dlv &>/dev/null; then
        echo "  dlv: $(dlv version 2>/dev/null | head -1)"
        return
    fi

    if command -v go &>/dev/null; then
        echo "  dlv: installing via go..."
        go install github.com/go-delve/delve/cmd/dlv@latest 2>/dev/null || true
        if [ -x "$HOME/go/bin/dlv" ]; then
            ln -sf "$HOME/go/bin/dlv" "$INSTALL_DIR/dlv" 2>/dev/null || true
            echo "  dlv: $(dlv version 2>/dev/null | head -1)"
        fi
    else
        echo "  dlv: go not found, skipping"
    fi
}

install_lldb_dap
install_debugpy
install_dlv

# ─────────────────────────────────────────────────
# Phase 5 — Verify
# ─────────────────────────────────────────────────
echo ""
echo "=== Verification ==="

echo -n "  omp:       "; omp --version 2>/dev/null || echo "NOT FOUND"

echo -n "  lldb-dap:  "
if command -v lldb-dap &>/dev/null; then
    LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH" ldd "$(which lldb-dap)" 2>/dev/null | grep -q "not found" && echo "INSTALLED (missing libs)" || echo "OK"
else
    echo "NOT FOUND"
fi

echo -n "  gdb:       "
command -v gdb &>/dev/null && echo "$(gdb --version 2>/dev/null | head -1)" || echo "NOT FOUND"

echo -n "  debugpy:   "
python3 -c "import debugpy; print(debugpy.__version__)" 2>/dev/null || echo "NOT INSTALLED"

echo -n "  dlv:       "
dlv version 2>/dev/null | head -1 || echo "NOT FOUND"

echo ""
echo "=== Done ==="
echo "Start omp:  cd <project> && omp"
echo "Config at:  ~/.omp/agent/models.yml"
