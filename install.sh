#!/usr/bin/env bash
# One-line installer:
#   curl -fsSL xian-jun.github.io/ranch | bash                      # set up this machine
#   curl -fsSL xian-jun.github.io/ranch | bash -s -- join           # just join the network; finish with `ranch add` from your main computer
#   curl -fsSL xian-jun.github.io/ranch | bash -s -- --team owner/ranch-config
# Fetches this repo into ~/.local/share/ranch, then runs bin/ranch with the same arguments.
set -euo pipefail

RANCH_REPO="${RANCH_REPO:-https://github.com/xian-jun/ranch.git}"
RANCH_TARBALL="${RANCH_TARBALL:-https://codeload.github.com/xian-jun/ranch/tar.gz/main}"
RANCH_HOME="${RANCH_HOME:-$HOME/.local/share/ranch}"

if [ -n "${RANCH_SOURCE_DIR:-}" ]; then
  # Local testing: run straight from a checkout.
  exec bash "$RANCH_SOURCE_DIR/bin/ranch" "$@"
fi

if [ -d "$RANCH_HOME/.git" ] && command -v git >/dev/null 2>&1; then
  git -C "$RANCH_HOME" pull --ff-only --quiet
elif command -v git >/dev/null 2>&1; then
  # Fresh install, or upgrading a git-less copy now that git exists.
  rm -rf "$RANCH_HOME"
  mkdir -p "$(dirname "$RANCH_HOME")"
  git clone --quiet "$RANCH_REPO" "$RANCH_HOME"
else
  # No git yet (minimal servers): fetch a snapshot. `ranch` installs git and switches to a clone later.
  rm -rf "$RANCH_HOME"
  mkdir -p "$RANCH_HOME"
  curl -fsSL "$RANCH_TARBALL" | tar -xz -C "$RANCH_HOME" --strip-components=1
fi

exec bash "$RANCH_HOME/bin/ranch" "$@"
