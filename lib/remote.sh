# Joining a server to the network, then setting it up from your main computer.
#
#   at the server:          ranch join        → Tailscale only, approved by scanning a QR code
#   on your main computer:  ranch add HOST    → full setup over Tailscale SSH, logins carried over

RANCH_URL="xian-jun.github.io/ranch"

ts_hostname() {
  "$(ts_bin)" status --json 2>/dev/null | sed -n 's/.*"HostName": *"\([^"]*\)".*/\1/p' | head -1
}

join_network() {
  [ "$OS" != macos ] || die "join is for Linux servers. On a Mac, just run: ranch"
  sudo_ready
  install_tailscale
  local ts
  ts="$(ts_bin)"
  [ -n "$ts" ] || die "Tailscale didn't install."

  step "Join your network"
  if "$ts" status >/dev/null 2>&1; then
    ok "already connected"
  else
    info "Scan this QR code with your phone and approve (or open the link on any device)."
    sudo "$ts" up --ssh --qr </dev/tty
  fi
  # Let your own devices SSH in with your Tailscale login; no keys or passwords.
  sudo "$ts" set --ssh
  ok "connected as $(ts_hostname); SSH from your devices enabled"

  step "Next, on your main computer"
  info "ranch add $(id -un)@$(ts_hostname)"
}

# --- on the main computer -------------------------------------------------

remote() { ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "$RANCH_TARGET" "$@"; }
remote_tty() { ssh -t -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "$RANCH_TARGET" "$@"; }

add_machine() {
  local target="${1:-}"
  [ -n "$target" ] || die "Usage: ranch add [user@]machine   (the name 'ranch join' printed)"
  case "$target" in *@*) ;; *) target="$(id -un)@$target" ;; esac
  RANCH_TARGET="$target"

  step "Connecting to $target"
  info "If Tailscale asks you to confirm, a link appears here; open it and approve."
  remote true || die "Couldn't connect. Check the name with 'tailscale status', and the user name on the server (ranch add user@machine)."
  ok "connected"

  step "Setting up $target"
  info "If it asks for a password, it's the server's password (nothing shows while you type)."
  remote_tty "curl -fsSL $RANCH_URL | bash -s -- --no-login"

  step "Carrying your logins over"
  carry_github
  carry_codex
  login_claude_remote

  step "$target"
  remote '$HOME/.local/bin/ranch login status' || true
  info "Done. Connect any time with: ssh $target"
}

carry_github() {
  local token
  token="$("$MISE" exec -- gh auth token 2>/dev/null || true)"
  if [ -z "$token" ]; then warn "GitHub: not signed in here, so nothing to carry over. Run 'ranch login' on the server."; return; fi
  printf '%s\n' "$token" | remote '$HOME/.local/bin/mise exec -- gh auth login --hostname github.com --git-protocol https --with-token && $HOME/.local/bin/mise exec -- gh auth setup-git' \
    && ok "GitHub: signed in as $("$MISE" exec -- gh api user --jq .login 2>/dev/null)" \
    || warn "GitHub: couldn't carry the login over. Run 'ranch login' on the server."
}

# Codex documents copying ~/.codex/auth.json as the way to sign in on a headless machine.
carry_codex() {
  local auth="$HOME/.codex/auth.json"
  if [ ! -f "$auth" ]; then warn "Codex: not signed in here, so nothing to carry over."; return; fi
  remote 'umask 077; mkdir -p "$HOME/.codex" && cat > "$HOME/.codex/auth.json"' < "$auth" \
    && ok "Codex: signed in" \
    || warn "Codex: couldn't copy the sign-in over."
}

# Claude Code keeps its Mac login in the keychain, so the server signs in itself;
# the link shows up in this terminal, where it's one click.
login_claude_remote() {
  if remote '$HOME/.local/bin/claude auth status 2>/dev/null' | grep -q '"loggedIn": *true'; then
    ok "Claude Code: already signed in"
    return
  fi
  info "Claude Code: open the link below, approve, then paste the code back here."
  remote_tty '$HOME/.local/bin/claude auth login' || warn "Claude Code: login skipped. Run 'ranch login' on the server."
}
