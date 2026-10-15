# Tailscale: a private network between your machines, nothing exposed to the internet.

TS_MAC_APP="/Applications/Tailscale.app"

ts_bin() {
  if has tailscale; then command -v tailscale
  elif [ -x "$TS_MAC_APP/Contents/MacOS/Tailscale" ]; then printf '%s' "$TS_MAC_APP/Contents/MacOS/Tailscale"
  fi
}

install_tailscale() {
  step "Tailscale (private network)"
  if [ -n "$(ts_bin)" ]; then
    ok "Tailscale installed"
    return
  fi
  case "$OS" in
    macos)
      local pkg
      pkg="$(mktemp -d)/Tailscale.pkg"
      curl -fsSL -o "$pkg" https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg
      info "Installing the Tailscale app (asks for your Mac password)"
      sudo installer -pkg "$pkg" -target / >/dev/null </dev/tty
      rm -f "$pkg"
      ;;
    *)
      curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1 || die "Tailscale install failed"
      ;;
  esac
  ok "installed Tailscale"
}

login_tailscale() {
  local ts
  ts="$(ts_bin)"
  if [ -z "$ts" ]; then info "· Tailscale    not installed"; return; fi
  if "$ts" status >/dev/null 2>&1; then
    ok "Tailscale    connected as $("$ts" status --json 2>/dev/null | sed -n 's/.*"HostName": *"\([^"]*\)".*/\1/p' | head -1)"
  elif [ "${1:-}" = run ]; then
    if [ "$OS" = macos ]; then
      open -a Tailscale
      info "→ Tailscale: click its icon in the menu bar, allow the VPN, and sign in."
      info "  Then run 'setup login status' to check."
    else
      info "→ Tailscale: open the link and sign in"
      # --ssh lets your other devices SSH in using your Tailscale login; no keys or passwords.
      sudo "$ts" up --ssh </dev/tty || warn "Tailscale login skipped"
      login_tailscale status
    fi
  else
    warn "Tailscale    not connected"
  fi
}
