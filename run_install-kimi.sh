#!/bin/sh
# Bootstrap the kimi-code CLI binary if missing.
# kimi-code is not mise-pinnable (absent from the mise registry, no release artifacts)
# and is not installed by scripts/setup.sh. Official installer:
# https://code.kimi.com/kimi-code/install.sh — creates ~/.kimi-code/bin/kimi
# plus the ~/.local/bin/kimi symlink, then self-updates in place.
# Runs on every apply; the executable guard makes the common case a no-op
# (while still self-healing the ~/.local/bin/kimi PATH symlink).
# Auth is deliberately NOT handled here: rotating OAuth credentials are never
# shipped through chezmoi, so a fresh node runs an interactive `kimi` login once.
if [ -x "$HOME/.kimi-code/bin/kimi" ]; then
  # Binary present: also ensure the PATH symlink survives. The installer
  # creates it once, but nothing recreated it once lost — a bare exit 0
  # here made that state permanent, silently dropping kimi off PATH.
  # -e is false for a dangling symlink too, so ln -sf repairs that as well;
  # a real file at the path is left untouched (kimi already reachable).
  if [ ! -e "$HOME/.local/bin/kimi" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$HOME/.kimi-code/bin/kimi" "$HOME/.local/bin/kimi"
  fi
  exit 0
fi
mkdir -p "$HOME/.kimi-code"
curl -fsSL https://code.kimi.com/kimi-code/install.sh -o "$HOME/.kimi-code/install.sh" && bash "$HOME/.kimi-code/install.sh"
