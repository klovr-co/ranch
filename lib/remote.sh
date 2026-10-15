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
  # Let this user publish T3 privately on Tailscale without sudo.
  sudo "$ts" set --operator="$(id -un)"
  # Keep background services (T3) running when nobody is logged in.
  sudo loginctl enable-linger "$(id -un)" 2>/dev/null || true
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
  remember_machine "$target"

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
  login_infisical_remote

  step "Pairing T3 Code with this computer"
  pair_t3

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

# Infisical on a server: no browser there, so sign in with email, password and 2FA code,
# typed here in this terminal. (Accounts that sign in with GitHub/Google can't do this.)
login_infisical_remote() {
  local inf='$HOME/.local/bin/mise exec -- infisical'
  if ! remote "$inf --version" >/dev/null 2>&1; then info "Infisical isn't installed on the server; skipping."; return; fi
  if ! remote "$inf login status 2>&1" | grep -qi 'not authenticated'; then ok "Infisical: already signed in"; return; fi
  can_prompt || { warn "Infisical: needs a terminal. Run 'infisical login --interactive' on the server."; return; }
  info "Infisical: choose your region, then type your Infisical email, password and 2FA code."
  remote_tty "$inf login --interactive" </dev/tty || true
  if remote "$inf login status 2>&1" | grep -qi 'not authenticated'; then
    warn "Infisical: not signed in. Run 'infisical login --interactive' on the server later."
  else
    ok "Infisical: signed in"
  fi
}

# --- status: this machine, the network, and every server you've added --------------

MACHINES_LIST="$HOME/.config/ranch/machines"

remember_machine() {
  mkdir -p "$(dirname "$MACHINES_LIST")"
  touch "$MACHINES_LIST"
  grep -qxF "$1" "$MACHINES_LIST" || echo "$1" >> "$MACHINES_LIST"
}

show_status() {
  run_logins status

  step "Your network (Tailscale)"
  local ts
  ts="$(ts_bin)"
  if [ -z "$ts" ] || ! "$ts" status >/dev/null 2>&1; then
    warn "Not connected to Tailscale"
  else
    # Columns: ip, name, user, os, state ("-" means connected; "offline" otherwise).
    "$ts" status 2>/dev/null | awk '$1 ~ /^100\./ {
      state = ($5 == "offline") ? "offline" : "online"
      mark = (state == "online") ? "\033[32m●\033[0m" : "\033[2m○\033[0m"
      printf "    %s %-22s %-8s %s\n", mark, $2, $4, state }'
  fi

  [ -s "$MACHINES_LIST" ] || return 0
  local target
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    step "$target"
    if ssh -o BatchMode=yes -o ConnectTimeout=8 "$target" '$HOME/.local/bin/ranch login status' 2>/dev/null \
        | grep -v '==> Logins' | sed '/^[[:space:]]*$/d'; then :
    else
      warn "unreachable (offline, or Tailscale SSH needs approval: try 'ssh $target')"
    fi
  done < "$MACHINES_LIST"
}

# Update every server you've added: each pulls the newest ranch and re-applies it (logins untouched).
update_all() {
  [ -s "$MACHINES_LIST" ] || { info "No servers added yet (ranch add [user@]machine)."; return 0; }
  local target
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    step "Updating $target"
    # -t so a password prompt (rare: only when new system packages are needed) can be answered here.
    if can_prompt; then
      ssh -t -o ConnectTimeout=10 "$target" "curl -fsSL $RANCH_URL | bash -s -- --no-login" </dev/tty \
        || warn "$target: update failed or unreachable"
    else
      ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" "curl -fsSL $RANCH_URL | bash -s -- --no-login" \
        || warn "$target: update failed or unreachable"
    fi
  done < "$MACHINES_LIST"
}
