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
      if ! sudo -n true 2>/dev/null && ! can_prompt; then
        warn "Skipped: installing Tailscale needs your Mac password, and there's no terminal to type it in."
        warn "Run ranch from the Terminal app to finish this step."
        return
      fi
      local pkg
      pkg="$(mktemp -d)/Tailscale.pkg"
      curl -fsSL -o "$pkg" https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg
      info "Installing the Tailscale app (asks for your Mac password)"
      if can_prompt; then sudo installer -pkg "$pkg" -target / >/dev/null </dev/tty
      else sudo installer -pkg "$pkg" -target / >/dev/null; fi
      rm -f "$pkg"
      ;;
    *)
      if ! sudo -n true 2>/dev/null && ! can_prompt; then
        warn "Skipped: installing Tailscale needs sudo, and there's no terminal to type the password in."
        return
      fi
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
      # The app's own sign-in buttons don't always open a browser (seen on macOS 27),
      # so get the link from the CLI, open it ourselves and wait for the sign-in.
      pgrep -qf "$TS_MAC_APP" || open -a Tailscale
      local out url i=0
      out="$(mktemp)"
      "$ts" up >"$out" 2>&1 &
      local pid=$!
      while [ $i -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
        url="$(grep -o 'https://login.tailscale.com/[^[:space:]]*' "$out" | head -1)"
        [ -n "$url" ] && break
        sleep 1; i=$((i + 1))
      done
      if [ -n "${url:-}" ]; then
        info "→ Tailscale: sign in at $url"
        info "  (opening it in your browser; if macOS asks to allow a VPN, click Allow)"
        open "$url"
        wait "$pid" || warn "Tailscale login didn't finish"
      else
        warn "Couldn't get a Tailscale sign-in link. Open the Tailscale app and allow its VPN, then run 'ranch login'."
        kill "$pid" 2>/dev/null || true
      fi
      rm -f "$out"
      login_tailscale status
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
