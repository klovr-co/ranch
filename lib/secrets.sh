# Secrets with Infisical.
#
# Your main computer signs in as you (browser). Each server gets its own limited login
# (an Infisical "machine identity"), created from your main computer by `ranch secrets connect`:
# no 2FA prompts or expiring sessions on the server, and you can revoke one server alone.
# Keys go straight from Infisical to the server over SSH; they're never printed.
#
# Code gets secrets at runtime, the same way everywhere:  ranch run -- pnpm dev

INFISICAL_API="${INFISICAL_API:-https://app.infisical.com/api}"
SERVER_SECRETS_FILE='$HOME/.config/ranch/infisical.env'   # expanded on the server

inf() { "$MISE" exec -- infisical "$@"; }

# Read one field from JSON on stdin: json_get '["identity"]["id"]'
json_get() { python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(eval("d"+sys.argv[1]))
except Exception: print("")' "$1"; }

api() { # api METHOD PATH [JSON]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -s -X "$method" -H "Authorization: Bearer $INF_TOKEN" -H 'Content-Type: application/json' "$INFISICAL_API$path" -d "$body"
  else
    curl -s -X "$method" -H "Authorization: Bearer $INF_TOKEN" "$INFISICAL_API$path"
  fi
}

# --- on your main computer: give a server its own Infisical login -------------------------

connect_secrets() {
  local target="${1:-}"
  [ -n "$target" ] || die "Usage: ranch secrets connect [user@]machine"
  case "$target" in *@*) ;; *) target="$(id -un)@$target" ;; esac
  RANCH_TARGET="$target"
  local name="${target#*@}"
  has python3 || die "ranch secrets needs python3 on this computer."

  step "Infisical login for $name"
  INF_TOKEN="$(inf user get token --plain 2>/dev/null | grep -oE 'eyJ[A-Za-z0-9._-]+' | head -1)"
  [ -n "$INF_TOKEN" ] || die "Sign in to Infisical on this computer first: ranch login"

  local org
  org="$(api GET /v2/users/me/organizations | json_get '["organizations"][0]["id"]')"
  [ -n "$org" ] || die "Couldn't find your Infisical organization."

  # Reuse the server's identity if it exists, otherwise create it with no access to anything yet.
  local iid
  iid="$(api GET "/v2/organizations/$org/identity-memberships" | python3 -c 'import sys,json
n=sys.argv[1]
for m in json.load(sys.stdin).get("identityMemberships",[]):
    i=m.get("identity",{})
    if i.get("name")==n: print(i.get("id")); break' "$name")"
  if [ -n "$iid" ]; then
    ok "using existing login \"$name\""
  else
    iid="$(api POST /v1/identities "{\"name\":\"$name\",\"organizationId\":\"$org\",\"role\":\"no-access\"}" | json_get '["identity"]["id"]')"
    [ -n "$iid" ] || die "Couldn't create a login for $name in Infisical."
    ok "created login \"$name\""
  fi

  # Universal Auth = client ID + secret. Attach it once; reuse it after.
  local cid
  cid="$(api GET "/v1/auth/universal-auth/identities/$iid" | json_get '["identityUniversalAuth"]["clientId"]')"
  if [ -z "$cid" ]; then
    cid="$(api POST "/v1/auth/universal-auth/identities/$iid" '{"accessTokenTTL":86400,"accessTokenMaxTTL":2592000}' \
      | json_get '["identityUniversalAuth"]["clientId"]')"
  fi
  [ -n "$cid" ] || die "Couldn't set up the login method for $name."

  # A fresh secret each time; it goes straight to the server and isn't kept here.
  local cs
  cs="$(api POST "/v1/auth/universal-auth/identities/$iid/client-secrets" "{\"description\":\"ranch: $name\"}" \
    | json_get '["clientSecret"]')"
  [ -n "$cs" ] || die "Couldn't create a key for $name."
  printf 'INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=%s\nINFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=%s\nINFISICAL_MACHINE_IDENTITY_ID=%s\n' "$cid" "$cs" "$iid" \
    | remote "umask 077; mkdir -p \$HOME/.config/ranch && cat > $SERVER_SECRETS_FILE" \
    || die "Couldn't save the key on $target."
  cs=""
  ok "key saved privately on $name (only readable by its user)"

  grant_projects "$org" "$iid"

  if remote '$HOME/.local/bin/ranch secrets check' >/dev/null 2>&1; then
    ok "$name can sign in to Infisical"
    # Only now that the new key is proven, retire the older ones so a server never keeps spare working keys.
    revoke_old_keys "$iid" "$name"
  else
    warn "$name couldn't sign in with its new key; run 'ranch secrets connect $target' again."
  fi
  INF_TOKEN=""
}

# Revoke every key ranch made for this server except the newest. Safe to run any time.
revoke_old_keys() {
  local iid="$1" name="$2" n
  n="$(api GET "/v1/auth/universal-auth/identities/$iid/client-secrets" | NAME="$name" python3 -c 'import sys,json,os
d=json.load(sys.stdin); rows=d.get("clientSecretData", d.get("clientSecrets", []))
mine=sorted((r for r in rows if r.get("description")=="ranch: "+os.environ["NAME"] and not r.get("isClientSecretRevoked")), key=lambda r: r.get("createdAt",""))
for r in mine[:-1]: print(r["id"])' | while read -r sid; do
      [ -n "$sid" ] || continue
      api POST "/v1/auth/universal-auth/identities/$iid/client-secrets/$sid/revoke" '{}' >/dev/null && echo x
    done | wc -l | tr -d ' ')"
  if [ "${n:-0}" -gt 0 ]; then ok "retired $n older key(s) for $name"; fi
}

# Read access to every project in the organization. Re-run `ranch secrets connect` after adding projects.
grant_projects() {
  local org="$1" iid="$2" pid n=0
  for pid in $(api GET "/v2/organizations/$org/workspaces" | python3 -c 'import sys,json
d=json.load(sys.stdin)
for w in d.get("workspaces",d.get("projects",[])): print(w["id"])'); do
    api POST "/v2/workspace/$pid/identity-memberships/$iid" '{"role":"viewer"}' >/dev/null
    n=$((n + 1))
  done
  if [ "$n" -gt 0 ]; then ok "read access to $n project(s)"; else info "No projects yet. After you add some, run this again to give the server access."; fi
}

# --- on any machine ----------------------------------------------------------------------

has_server_login() { [ -f "$HOME/.config/ranch/infisical.env" ]; }
has_user_login() { ! inf login status 2>&1 | grep -qi 'not authenticated'; }

server_token() {
  # shellcheck disable=SC1090
  ( set -a; . "$HOME/.config/ranch/infisical.env"; set +a
    inf login --method=universal-auth --client-id "$INFISICAL_UNIVERSAL_AUTH_CLIENT_ID" \
      --client-secret "$INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET" --silent --plain 2>/dev/null | tail -1 )
}

# A server's own key (from `ranch secrets connect`) always wins over a personal login, so a server never
# depends on, or opens a browser for, someone's session.
secrets_check() {
  if has_server_login; then
    case "$(server_token)" in eyJ*) return 0 ;; *) return 1 ;; esac
  fi
  has_user_login
}

# A machine login (a server) can't read the project from .infisical.yaml; infisical wants --projectId.
# Find the repo's link file (this folder or any above) and print its project id.
project_id_here() {
  local d="$PWD" f
  while [ -n "$d" ]; do
    f="$d/.infisical.yaml"
    if [ -f "$f" ]; then
      awk '/^[[:space:]]*project-id:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/["'"'"'[:space:]]/, ""); print; exit }' "$f"
      return 0
    fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
}

# ranch run [--env dev] [--projectId ID] -- command…   (the project comes from .infisical.yaml if present)
secrets_run() {
  # Keep the leading "--": without it infisical reads a command's own flags (like sh -c) as its own.
  if has_server_login; then
    local t
    t="$(server_token)"
    case "$t" in eyJ*) ;; *) die "This machine's Infisical login failed. From your main computer: ranch secrets connect $(id -un)@$(hostname)" ;; esac
    local pid=""
    case " $* " in *" --projectId"*) ;; *) pid="$(project_id_here)" ;; esac
    if [ -n "$pid" ]; then
      INFISICAL_TOKEN="$t" exec "$MISE" exec -- infisical run --projectId "$pid" "$@"
    fi
    INFISICAL_TOKEN="$t" exec "$MISE" exec -- infisical run "$@"
  elif has_user_login; then
    exec "$MISE" exec -- infisical run "$@"
  else
    die "Not signed in to Infisical. Main computer: ranch login. Server: ranch secrets connect from your main computer."
  fi
}

# --- keep Convex in step with Infisical -------------------------------------------------------

# Run infisical with whichever login this machine has (yours, or the server's own).
secrets_inf() {
  local t
  if has_server_login; then
    t="$(server_token)"
    case "$t" in eyJ*) ;; *) die "This machine's Infisical login failed. From your main computer: ranch secrets connect $(id -un)@$(hostname)" ;; esac
    local pid=""
    case " $* " in *" --projectId"*) ;; *) pid="$(project_id_here)" ;; esac
    if [ -n "$pid" ]; then
      INFISICAL_TOKEN="$t" inf "$1" --projectId "$pid" "${@:2}"
    else
      INFISICAL_TOKEN="$t" inf "$@"
    fi
  elif has_user_login; then
    inf "$@"
  else
    die "Not signed in to Infisical. Main computer: ranch login. Server: ranch secrets connect from your main computer."
  fi
}

# Which Infisical folder a command reads and writes: --path, else `path:` in .ranch/secrets.yaml, else the root.
# A repo with one app keeps everything in the root; a repo with several apps gives each its own folder (/backend, /web).
secrets_path() {   # secrets_path ROOT [args…]
  local root="$1" p=""; shift
  while [ $# -gt 0 ]; do
    case "$1" in --path) p="${2:-}"; break ;; --path=*) p="${1#--path=}"; break ;; esac
    shift
  done
  if [ -z "$p" ] && [ -f "$root/.ranch/secrets.yaml" ]; then
    p="$(awk '/^path:/ { sub(/^path:[[:space:]]*/, ""); gsub(/["'"'"'[:space:]]/, ""); print; exit }' "$root/.ranch/secrets.yaml")"
  fi
  p="${p:-/}"
  case "$p" in /*) printf '%s' "$p" ;; *) die "--path must start with / (for example /backend), not '$p'." ;; esac
}

# ranch secrets push|status <env> [--to DEPLOYMENT] [--yes]   (run inside the repo)
# One way: Infisical -> Convex. Reads .ranch/secrets.yaml. Never deletes, never prints a value.
sync_secrets() {
  local mode="$1" envname="${2:-}"
  [ -n "$envname" ] && [ "${envname#-}" = "$envname" ] || die "Usage: ranch secrets $mode <env> [--to DEPLOYMENT] [--yes]   (env is dev or prod)"
  shift 2
  has python3 || die "ranch secrets $mode needs python3."
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this inside the repo."
  local tmp rc=0; tmp="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/ranch-sync.XXXXXX")"
  local spath; spath="$(secrets_path "$root" "$@")" || { rm -rf "$tmp"; exit 1; }
  ( cd "$root" && secrets_inf export --env="$envname" --path "$spath" --format=json --silent > "$tmp/export.json" ) \
    || { rm -rf "$tmp"; die "Couldn't read the $envname secrets in folder $spath from Infisical (is this repo linked? .infisical.yaml)."; }
  ( cd "$root" && python3 -I "$ROOT/lib/secrets_sync.py" "$mode" "$envname" "$tmp/export.json" "$@" ) || rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# ranch secrets import <env> --from-convex DEPLOYMENT | --from-file PATH | --from-cloudrun SERVICE  [options]
# First-time load of a repo's secrets into an Infisical environment. One way: source -> Infisical.
# Never deletes, never prints a value, keeps existing values unless --overwrite. Needs your own login
# (servers only have read access).
import_secrets() {
  local envname="${1:-}"
  [ -n "$envname" ] && [ "${envname#-}" = "$envname" ] || die "Usage: ranch secrets import <env> --from-convex DEPLOYMENT | --from-file PATH | --from-cloudrun SERVICE   (env is dev, staging or prod)"
  shift
  has python3 || die "ranch secrets import needs python3."
  has_user_login || die "Importing writes to Infisical, so it needs your own sign-in on this computer: ranch login"
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this inside the repo."
  [ -f "$root/.infisical.yaml" ] || die "This repo isn't linked to an Infisical project yet. Run 'infisical init' in $root first."
  local tmp rc=0; tmp="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/ranch-import.XXXXXX")"
  local ipath; ipath="$(secrets_path "$root" "$@")" || { rm -rf "$tmp"; exit 1; }
  ( cd "$root" && inf export --env="$envname" --path "$ipath" --format=json --silent > "$tmp/export.json" ) \
    || { rm -rf "$tmp"; die "Couldn't read the $envname environment (folder $ipath) from Infisical. Does the folder exist in the project?"; }
  python3 -I "$ROOT/lib/secrets_import.py" "$envname" "$tmp/export.json" "$tmp/apply.yaml" --root "$root" "$@" || rc=$?
  if [ "$rc" -eq 10 ]; then
    if ( cd "$root" && inf secrets set --env="$envname" --path "$ipath" --file "$tmp/apply.yaml" --silent >/dev/null ); then
      ok "loaded into Infisical $envname ($ipath). Check: ranch secrets status $envname (if this repo pushes to Convex)"
      rc=0
    else
      warn "Infisical rejected the load; nothing was changed that you need to undo."
      rc=1
    fi
  fi
  rm -rf "$tmp"
  return "$rc"
}

# ranch secrets grant [machine]   (from your main computer)
# Give servers you already connected read access to projects created since. Doesn't touch their keys.
grant_servers() {
  local only="${1:-}"
  has python3 || die "ranch secrets grant needs python3 on this computer."
  INF_TOKEN="$(inf user get token --plain 2>/dev/null | grep -oE 'eyJ[A-Za-z0-9._-]+' | head -1)"
  [ -n "$INF_TOKEN" ] || die "Sign in to Infisical on this computer first: ranch login"
  local org; org="$(api GET /v2/users/me/organizations | json_get '["organizations"][0]["id"]')"
  [ -n "$org" ] || die "Couldn't find your Infisical organization."

  step "Servers connected with ranch"
  local line iid name n=0
  while IFS="$(printf '\t')" read -r iid name; do
    [ -n "$iid" ] || continue
    [ -z "$only" ] || [ "$name" = "${only#*@}" ] || continue
    # Only logins that `ranch secrets connect` made (their key is described "ranch: <name>").
    api GET "/v1/auth/universal-auth/identities/$iid/client-secrets" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
rows=d.get("clientSecretData", d.get("clientSecrets", []))
sys.exit(0 if any(str(s.get("description","")).startswith("ranch: ") and not s.get("isClientSecretRevoked") for s in rows) else 1)' || continue
    info "$name"
    grant_projects "$org" "$iid"
    n=$((n + 1))
  done <<EOT
$(api GET "/v2/organizations/$org/identity-memberships" | python3 -c 'import sys,json
for m in json.load(sys.stdin).get("identityMemberships",[]):
    i=m.get("identity",{}); print(i.get("id","")+"\t"+i.get("name",""))')
EOT
  INF_TOKEN=""
  [ "$n" -gt 0 ] || info "No servers connected yet. Run: ranch secrets connect [user@]machine"
}
