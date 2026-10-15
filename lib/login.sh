# Logins: show what's signed in, walk through what isn't.
# Every flow prints a link + code, so a machine with no screen can be approved from a phone or another computer.

# Under `curl | bash`, stdin is the script itself; interactive steps must read the real terminal.
can_prompt() { [ -t 1 ] && { : </dev/tty; } 2>/dev/null; }

gh_cmd() { "$MISE" exec -- gh "$@"; }

# No screen (e.g. an SSH session or Ubuntu Server): there's no browser to open,
# so sign-ins are approved from another device instead.
headless() {
  [ "$OS" != macos ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]
}

# GitHub device login. On a headless machine, don't try to open a browser:
# GH_BROWSER=true makes gh skip it and just wait for the code to be entered elsewhere.
gh_login() {
  if headless; then
    info "→ GitHub: on your phone or another computer, open https://github.com/login/device"
    info "  and enter the code shown below. This terminal continues once you approve."
    GH_BROWSER=true gh_cmd auth login --hostname github.com --git-protocol https --web </dev/tty
  else
    info "→ GitHub: open the link and enter the code"
    gh_cmd auth login --hostname github.com --git-protocol https --web </dev/tty
  fi
}

login_github() {
  if gh_cmd auth status >/dev/null 2>&1; then
    ok "GitHub       $(gh_cmd api user --jq .login 2>/dev/null)"
  elif [ "${1:-}" = run ]; then
    gh_login || warn "GitHub login skipped"
    login_github status
  else
    warn "GitHub       not signed in"
  fi
}

login_claude() {
  if ! has claude; then warn "Claude Code  not installed"; return; fi
  if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
    ok "Claude Code  $(claude auth status 2>/dev/null | sed -n 's/.*"email": *"\([^"]*\)".*/\1/p')"
  elif [ "${1:-}" = run ]; then
    if headless; then
      info "→ Claude Code: open the link below on your phone or another computer, approve,"
      info "  then paste the code it gives you back here."
    else
      info "→ Claude Code: open the link and approve"
    fi
    claude auth login </dev/tty || warn "Claude login skipped"
    login_claude status
  else
    warn "Claude Code  not signed in"
  fi
}

login_codex() {
  if ! has codex; then warn "Codex        not installed"; return; fi
  if codex login status 2>&1 | grep -qi '^logged in'; then
    ok "Codex        $(codex login status 2>&1 | head -1)"
  elif [ "${1:-}" = run ]; then
    info "→ Codex: open the link below on your phone or another computer and enter the code"
    codex login --device-auth </dev/tty || warn "Codex login skipped"
    login_codex status
  else
    warn "Codex        not signed in"
  fi
}

# Infisical: your secrets, injected at runtime. Each of your own machines signs in as you.
login_secrets() {
  local inf="$MISE exec -- infisical"
  if ! "$MISE" which infisical >/dev/null 2>&1; then info "· Secrets      Infisical not installed"; return; fi
  local st
  st="$($inf login status 2>&1 || true)"
  if ! printf '%s' "$st" | grep -qi 'not authenticated'; then
    ok "Secrets      Infisical $(printf '%s' "$st" | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' | head -1)"
  elif [ -f "$HOME/.config/ranch/infisical.env" ]; then
    ok "Secrets      Infisical (this server's own login)"
  elif headless; then
    warn "Secrets      Infisical not connected (from your main computer: ranch secrets connect $(id -un)@$(hostname))"
  elif [ "${1:-}" = run ]; then
    info "→ Infisical: choose your region (US unless you picked EU), then sign in in the browser"
    $inf login </dev/tty || warn "Infisical login skipped"
    login_secrets status
  else
    warn "Secrets      Infisical not signed in"
  fi
}

# ranch login        → sign in to anything missing
# ranch login status → only report
run_logins() {
  local mode="${1:-run}"
  step "Logins"
  if [ "$mode" = run ] && ! can_prompt; then
    warn "No terminal to ask on; run 'ranch login' yourself to sign in."
    mode=status
  fi
  login_github "$mode"
  login_tailscale "$mode"
  login_secrets "$mode"
  login_claude "$mode"
  login_codex "$mode"
  login_t3
}
