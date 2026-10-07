#!/bin/sh
# Bootstrap the kimi-code CLI binary if missing.
# kimi-code is not mise-pinnable (absent from the mise registry, no release artifacts)
# and is not installed by scripts/setup.sh. Official installer:
# https://code.kimi.com/kimi-code/install.sh — creates ~/.kimi-code/bin/kimi
# plus the ~/.local/bin/kimi symlink, then self-updates in place.
# Runs on every apply; the executable guard makes the common case a no-op.
# Auth is deliberately NOT handled here: rotating OAuth credentials are never
# shipped through chezmoi, so a fresh node runs an interactive `kimi` login once.
if [ -x "$HOME/.kimi-code/bin/kimi" ]; then
  exit 0
fi
curl -fsSL https://code.kimi.com/kimi-code/install.sh -o "$HOME/.kimi-code/install.sh" && bash "$HOME/.kimi-code/install.sh"
