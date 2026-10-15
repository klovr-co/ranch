# Shared helpers. Must stay compatible with bash 3.2 (macOS default).

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

# Read `key = "value"` from a flat TOML file. Prints the value, or $3 if missing.
conf_get() {
  local file="$1" key="$2" fallback="${3:-}" value=""
  if [ -f "$file" ]; then
    value=$(awk -v k="$key" '
      /^[[:space:]]*#/ { next }
      {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        if (index(line, k) != 1) next
        rest = substr(line, length(k) + 1)
        if (rest !~ /^[[:space:]]*=/) next
        sub(/^[[:space:]]*=[[:space:]]*/, "", rest)
        sub(/[[:space:]]+#.*$/, "", rest)
        gsub(/^"|"$/, "", rest)
        print rest
        exit
      }' "$file")
  fi
  if [ -n "$value" ]; then printf '%s' "$value"; else printf '%s' "$fallback"; fi
}

# Append a line to a file once.
append_once() {
  local file="$1" line="$2"
  touch "$file"
  grep -qxF "$line" "$file" || printf '\n%s\n' "$line" >> "$file"
}

# Symlink src -> dest, but never clobber a real file someone wrote by hand.
link_file() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] || [ ! -e "$dest" ]; then
    ln -sfn "$src" "$dest"
    ok "linked $(basename "$dest") → $dest"
  else
    warn "$dest exists and is not managed by setup; left it alone"
  fi
}
