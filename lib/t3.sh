# T3 Code: servers run it in the background; your main computer's T3 app controls them over Tailscale.
# Skip it with RANCH_T3=0.

t3_wanted() { [ "${RANCH_T3:-1}" != 0 ]; }

# Servers (Linux) run T3. On a Mac you use the T3 Code app, so there's nothing to install.
install_t3() {
  t3_wanted || return 0
  [ "$OS" != macos ] || return 0
  step "T3 Code (control agents from your other devices)"
  if has t3; then
    t3 update >/dev/null 2>&1 || true
    ok "t3 $(t3 --version 2>/dev/null | awk '{print $2}')"
  else
    curl -fsSL https://t3.codes/install.sh | sh >/dev/null 2>&1 || { warn "T3 install failed; skipping"; return 0; }
    ok "installed t3"
  fi

  # Background services don't load your shell, so tell T3 where Claude Code and mise tools (Codex) live.
  local dropin="$HOME/.config/systemd/user/t3code.service.d"
  mkdir -p "$dropin"
  printf '[Service]\n# Added by ranch: let T3 find Claude Code (~/.local/bin) and mise tools like Codex.\nEnvironment=PATH=%s/.local/bin:%s/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' \
    "$HOME" "$HOME" > "$dropin/ranch-path.conf"

  if systemctl --user is-active --quiet t3code 2>/dev/null; then
    systemctl --user daemon-reload && systemctl --user restart t3code
  else
    t3 service install >/dev/null 2>&1 || { warn "Couldn't start T3 in the background"; return 0; }
    systemctl --user daemon-reload && systemctl --user restart t3code
  fi
  if systemctl --user is-active --quiet t3code; then ok "T3 running in the background"; else warn "T3 service isn't running"; fi
}

login_t3() {
  t3_wanted || return 0
  [ "$OS" != macos ] || return 0
  if ! has t3; then info "· T3 Code      not installed"; return; fi
  local n
  n="$(t3 auth session list 2>/dev/null | grep -c '^  client:' || true)"
  if [ "${n:-0}" -gt 0 ]; then ok "T3 Code      running, $n device(s) paired"
  elif systemctl --user is-active --quiet t3code 2>/dev/null; then warn "T3 Code      running, no devices paired (ranch pair from your main computer)"
  else warn "T3 Code      not running"; fi
}

# --- on the main computer: pair a server's T3 with your T3 app ------------------

pair_t3() {
  t3_wanted || return 0
  remote 'command -v $HOME/.local/bin/t3 >/dev/null' 2>/dev/null || { info "T3 isn't installed on the server; skipping pairing."; return 0; }
  local out url try
  for try in 1 2; do
    out="$(remote '$HOME/.local/bin/t3 pair --tailscale --label "'"$(scutil --get ComputerName 2>/dev/null || hostname)"'" --ttl 30m 2>&1')" || true
    url="$(printf '%s' "$out" | grep -o 'https://[^[:space:]]*/pair#token=[A-Za-z0-9]*' | head -1)"
    [ -n "$url" ] && break
    # First time on a Tailscale account, private HTTPS must be switched on once.
    local enable
    enable="$(remote 'timeout 10 tailscale serve --https=443 --bg http://127.0.0.1:3773 2>&1' | grep -o 'https://login.tailscale.com/f/serve[^[:space:]]*' | head -1)"
    if [ -n "$enable" ] && [ "$try" = 1 ] && can_prompt; then
      info "Tailscale needs a one-time approval for private HTTPS addresses (once per account)."
      open_link "$enable"
      printf '    Approve it in the browser, then press Enter: ' >/dev/tty; read -r _ </dev/tty
      continue
    fi
    break
  done
  if [ -z "$url" ]; then
    warn "T3: couldn't create a pairing link. Run 'ranch pair $RANCH_TARGET' to try again."
    return 0
  fi
  printf '%s' "$url" | pbcopy 2>/dev/null || true
  local app
  app="$(ls -d /Applications/T3\ Code*.app 2>/dev/null | head -1)"
  [ -n "$app" ] && open -a "$app"
  ok "T3: pairing link copied (valid 30 min)"
  info "In T3 Code: Settings → Connections → Add environment → paste (⌘V)."
  info "$url"
  [ -n "$app" ] || info "No T3 Code app found here; get it at https://t3.codes, or scan the QR code with the phone app."
}
