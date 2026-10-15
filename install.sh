#!/usr/bin/env bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/xian-jun/ranch/main/install.sh | bash -s -- --team owner/ranch-config
# Fetches this repo into ~/.local/share/ranch, then runs bin/ranch with the same arguments.
set -euo pipefail

RANCH_REPO="${RANCH_REPO:-https://github.com/xian-jun/ranch.git}"
RANCH_HOME="${RANCH_HOME:-$HOME/.local/share/ranch}"

if [ -n "${RANCH_SOURCE_DIR:-}" ]; then
  # Local testing: run straight from a checkout.
  exec bash "$RANCH_SOURCE_DIR/bin/ranch" "$@"
fi

if ! command -v git >/dev/null 2>&1; then
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "git is missing. Run: xcode-select --install   then re-run this line." >&2
  else
    echo "git is missing. Install it with your package manager, then re-run this line." >&2
  fi
  exit 1
fi

if [ -d "$RANCH_HOME/.git" ]; then
  git -C "$RANCH_HOME" pull --ff-only --quiet
else
  mkdir -p "$(dirname "$RANCH_HOME")"
  git clone --quiet "$RANCH_REPO" "$RANCH_HOME"
fi

exec bash "$RANCH_HOME/bin/ranch" "$@"
