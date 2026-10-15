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

# Claude Code keeps its Mac login in the keychain, so the server signs in itself.
# The login runs on the server inside tmux; we read its link, open it here, and type the code back.
# Built to survive a flaky browser: Chrome first, link also on the clipboard, codes from old links
# refused, real success checked, fresh link on retry.

open_link() {
  local url="$1" browser="${RANCH_BROWSER:-}"
  printf '%s' "$url" | pbcopy 2>/dev/null || true
  if [ -z "$browser" ] && [ -d "/Applications/Google Chrome.app" ]; then browser="Google Chrome"; fi
  if [ -n "$browser" ]; then open -a "$browser" "$url" 2>/dev/null || open "$url"; else open "$url"; fi
  info "Opened in ${browser:-your browser}. The link is also on your clipboard if you'd rather paste it elsewhere:"
  info "$url"
}

claude_remote_signed_in() {
  remote '$HOME/.local/bin/claude auth status 2>/dev/null' | grep -q '"loggedIn": *true'
}

login_claude_remote() {
  if claude_remote_signed_in; then ok "Claude Code: already signed in"; return; fi
  can_prompt || { warn "Claude Code: needs a terminal to paste the code. Run 'ranch add' from Terminal."; return; }

  local try url state code answer
  for try in 1 2 3; do
    # Fresh login each attempt; the old link stops working, so no stale codes.
    url="$(remote 'tmux kill-session -t ranch-claude 2>/dev/null
      tmux new-session -d -s ranch-claude -x 500 -y 50 "$HOME/.local/bin/claude auth login; sleep 600"
      for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        u=$(tmux capture-pane -t ranch-claude -p -J | grep -o "https://[^[:space:]]*oauth/authorize[^[:space:]]*" | head -1)
        [ -n "$u" ] && { echo "$u"; break; }
      done')"
    if [ -z "$url" ]; then warn "Claude Code: couldn't start the login on the server."; break; fi
    state="$(printf '%s' "$url" | sed -n 's/.*[?&]state=\([^&]*\).*/\1/p')"

    info "Claude Code: sign in, click Authorize, then paste the code here."
    open_link "$url"

    while :; do
      printf '    Code (or Enter for a new link, s to skip): ' >/dev/tty
      IFS= read -r code </dev/tty || code=s
      code="$(printf '%s' "$code" | tr -d '[:space:]')"
      case "$code" in
        s|S) remote 'tmux kill-session -t ranch-claude 2>/dev/null' || true
             warn "Claude Code: skipped. Run 'ranch login' on the server later."; return ;;
        "") continue 2 ;;
      esac
      # The part after # is the link's state; it must match the link we opened.
      case "$code" in
        *"#"*) [ "${code##*#}" = "$state" ] || { warn "That code is from an older link. Use the newest tab, or press Enter for a new link."; continue; } ;;
      esac
      break
    done

    printf '%s' "$code" | remote 'tmux send-keys -t ranch-claude -l "$(cat)"; tmux send-keys -t ranch-claude Enter; sleep 5'
    if claude_remote_signed_in; then
      remote 'tmux kill-session -t ranch-claude 2>/dev/null' || true
      ok "Claude Code: signed in"
      return
    fi
    warn "Claude Code: that didn't work (the code may have expired)."
    printf '    Press Enter for a new link, or s to skip: ' >/dev/tty
    IFS= read -r answer </dev/tty || answer=s
    case "$answer" in s|S) break ;; esac
  done
  remote 'tmux kill-session -t ranch-claude 2>/dev/null' || true
  warn "Claude Code: not signed in. Run 'ranch login' on the server, or 'ranch add' again."
}
