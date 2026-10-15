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
  else
    warn "$name couldn't sign in with its new key; run 'ranch secrets connect $target' again."
  fi
  INF_TOKEN=""
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

secrets_check() {
  if has_user_login; then return 0; fi
  has_server_login || return 1
  case "$(server_token)" in eyJ*) return 0 ;; *) return 1 ;; esac
}

# ranch run [--env dev] [--projectId ID] -- command…   (the project comes from .infisical.yaml if present)
secrets_run() {
  [ "${1:-}" != "--" ] || shift
  if has_user_login; then
    exec "$MISE" exec -- infisical run "$@"
  elif has_server_login; then
    local t
    t="$(server_token)"
    case "$t" in eyJ*) ;; *) die "This machine's Infisical login failed. From your main computer: ranch secrets connect $(id -un)@$(hostname)" ;; esac
    INFISICAL_TOKEN="$t" exec "$MISE" exec -- infisical run "$@"
  else
    die "Not signed in to Infisical. Main computer: ranch login. Server: ranch secrets connect from your main computer."
  fi
}
