#!/usr/bin/env bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/xian-jun/setup/main/install.sh | bash -s -- --team owner/setup-config
# Fetches this repo into ~/.local/share/setup, then runs bin/setup with the same arguments.
set -euo pipefail

SETUP_REPO="${SETUP_REPO:-https://github.com/xian-jun/setup.git}"
SETUP_HOME="${SETUP_HOME:-$HOME/.local/share/setup}"

if [ -n "${SETUP_SOURCE_DIR:-}" ]; then
  # Local testing: run straight from a checkout.
  exec bash "$SETUP_SOURCE_DIR/bin/setup" "$@"
fi

if ! command -v git >/dev/null 2>&1; then
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "git is missing. Run: xcode-select --install   then re-run this line." >&2
  else
    echo "git is missing. Install it with your package manager, then re-run this line." >&2
  fi
  exit 1
fi

if [ -d "$SETUP_HOME/.git" ]; then
  git -C "$SETUP_HOME" pull --ff-only --quiet
else
  mkdir -p "$(dirname "$SETUP_HOME")"
  git clone --quiet "$SETUP_REPO" "$SETUP_HOME"
fi

exec bash "$SETUP_HOME/bin/setup" "$@"
