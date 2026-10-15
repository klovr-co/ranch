# Team configs: a (private) repo with setup.toml, mise.toml and agent rules.
# Each team gets its own folder, ~/code/<team>/, and its rules and tools apply only inside it.

CONFIG_HOME="$HOME/.config/setup"
TEAMS_LIST="$CONFIG_HOME/teams"
CODE_HOME="${SETUP_CODE_HOME:-$HOME/code}"

remember_team() {
  mkdir -p "$CONFIG_HOME"
  touch "$TEAMS_LIST"
  grep -qxF "$1" "$TEAMS_LIST" || echo "$1" >> "$TEAMS_LIST"
}

ensure_gh_auth() {
  if ! "$MISE" exec -- gh auth status >/dev/null 2>&1; then
    info "Sign in to GitHub so setup can read your team config:"
    "$MISE" exec -- gh auth login --hostname github.com --git-protocol https --web </dev/tty
  fi
}

# Fetch or update a team config. Accepts owner/repo or a local path (for testing).
fetch_team() {
  local ref="$1" dir
  if [ -d "$ref" ]; then
    printf '%s' "$(cd "$ref" && pwd)"
    return
  fi
  dir="$CONFIG_HOME/teams.d/${ref//\//__}"
  # Everything except the final path goes to stderr: callers capture stdout.
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only --quiet >&2
  else
    ensure_gh_auth >&2
    mkdir -p "$(dirname "$dir")"
    "$MISE" exec -- gh repo clone "$ref" "$dir" -- --quiet >&2
  fi
  printf '%s' "$dir"
}

apply_team() {
  local ref="$1" dir name folder
  dir="$(fetch_team "$ref")"
  [ -f "$dir/setup.toml" ] || die "$ref has no setup.toml; is it a setup config repo?"
  name="$(conf_get "$dir/setup.toml" name "${ref%%/*}")"
  folder="$CODE_HOME/$(conf_get "$dir/setup.toml" folder "$name")"
  step "Team: $name → $folder"
  mkdir -p "$folder"

  # Agent rules: Claude Code and Codex read these from parent folders,
  # so they apply to every repo under the team folder and nowhere else.
  [ -f "$dir/agent/CLAUDE.md" ] && link_file "$dir/agent/CLAUDE.md" "$folder/CLAUDE.md"
  [ -f "$dir/agent/AGENTS.md" ] && link_file "$dir/agent/AGENTS.md" "$folder/AGENTS.md"

  # Team tools: mise picks up mise.toml from parent folders too.
  if [ -f "$dir/mise.toml" ]; then
    link_file "$dir/mise.toml" "$folder/mise.toml"
    "$MISE" trust --quiet "$folder/mise.toml" >/dev/null
    (cd "$folder" && "$MISE" --quiet install --yes >/dev/null)
    ok "team tools installed"
  fi

  local secrets
  secrets="$(conf_get "$dir/setup.toml" secrets "")"
  [ -n "$secrets" ] && info "secrets: $secrets (connected in a later step)"
  return 0
}
