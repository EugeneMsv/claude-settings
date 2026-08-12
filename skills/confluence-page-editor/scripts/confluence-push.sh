#!/usr/bin/env bash
# confluence-push.sh — Create or update a Confluence page via REST API
#
# Flags:
#   -a, --action      create|update (required)
#   -f, --file        path to ADF body JSON file (required)
#   -t, --title       page title (required)
#   -p, --page-id     page ID — required for update
#   -s, --space-id    space ID — required for create
#   -P, --parent-id   parent page ID — required for create
#   -v, --version     version number for update (default: auto-fetched)
#   -m, --message     version message (optional)
#   -u, --base-url    Confluence base URL (default: $CONFLUENCE_BASE_URL, see .env)
#   -h, --help        show this help
#
# Auth / config:
#   Credentials and site URL are read from a .env file next to this script
#   (scripts/.env — CONFLUENCE_BASE_URL / ATLASSIAN_EMAIL / ATLASSIAN_TOKEN),
#   not tracked in git. Env vars already exported in the shell take
#   precedence over it. This is the only place org-specific values (site
#   URL, email, token) should live — everything else in this skill is
#   org-agnostic.
#
# Examples:
#   # Create
#   confluence-push.sh -a create -s 278200320 -P 278201552 -t "My Page" -f body.json
#
#   # Update (auto-fetch current version — NOT safe against concurrent edits,
#   # see the optimistic-locking note below; prefer explicit -v)
#   confluence-push.sh -a update -p 1375277721 -t "My Page" -f body.json
#
#   # Update with explicit version and message (recommended — see below)
#   confluence-push.sh -a update -p 1375277721 -v 2 -t "My Page" -f body.json -m "Fix diagrams"
#
# Optimistic locking:
#   Confluence's v2 API enforces version.number as an optimistic lock, not an
#   HTTP conditional header (no If-Match/ETag support) — the PUT body's
#   version.number must be exactly current+1 or the API rejects the write.
#   Auto-fetch mode (-v omitted) fetches "current" at PUSH time and blindly
#   submits current+1 — so if someone edited the page between your read and
#   your push, auto-fetch silently overwrites their edit instead of being
#   rejected, because it never compares against the version YOU built against.
#   Prefer: read the page with confluence-get.sh (which prints
#   "NEXT VERSION TO PUSH"), build your edit against that snapshot, then pass
#   that exact number via -v here. If the live version has moved on, this
#   push will be rejected — re-fetch, diff, and reapply your edit against the
#   new content; do not just retry with version+1, which repeats the same
#   silent-overwrite risk.

set -euo pipefail

# Only source .env if the shell doesn't already have these exported — lets a
# caller override with their own `export ATLASSIAN_TOKEN=...` without .env
# clobbering it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${ATLASSIAN_TOKEN:-}" && -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

BASE_URL="${CONFLUENCE_BASE_URL:-}"
ACTION=""
FILE=""
TITLE=""
PAGE_ID=""
SPACE_ID=""
PARENT_ID=""
VERSION=""
MESSAGE="Updated via confluence-push.sh"

usage() {
  awk '/^# confluence-push/{p=1} p && /^[^#]/{exit} p{sub(/^# ?/,""); print}' "$0"
  exit "${1:-0}"
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--action)    ACTION="$2";    shift 2 ;;
    -f|--file)      FILE="$2";      shift 2 ;;
    -t|--title)     TITLE="$2";     shift 2 ;;
    -p|--page-id)   PAGE_ID="$2";   shift 2 ;;
    -s|--space-id)  SPACE_ID="$2";  shift 2 ;;
    -P|--parent-id) PARENT_ID="$2"; shift 2 ;;
    -v|--version)   VERSION="$2";   shift 2 ;;
    -m|--message)   MESSAGE="$2";   shift 2 ;;
    -u|--base-url)  BASE_URL="$2";  shift 2 ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown flag: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "${ATLASSIAN_TOKEN:-}" || -z "${ATLASSIAN_EMAIL:-}" ]]; then
  echo "ERROR: ATLASSIAN_EMAIL/ATLASSIAN_TOKEN not set — expected them exported" \
       "or in $SCRIPT_DIR/.env" >&2
  exit 1
fi
if [[ -z "$BASE_URL" ]]; then
  echo "ERROR: no Confluence base URL — set CONFLUENCE_BASE_URL in" \
       "$SCRIPT_DIR/.env, or pass -u/--base-url explicitly" >&2
  exit 1
fi
AUTH_HEADER="Basic $(echo -n "${ATLASSIAN_EMAIL}:${ATLASSIAN_TOKEN}" | base64)"

# Validate common required flags
if [[ -z "$ACTION" ]]; then echo "ERROR: -a/--action is required (create|update)" >&2; exit 1; fi
if [[ -z "$FILE" ]];   then echo "ERROR: -f/--file is required" >&2; exit 1; fi
if [[ -z "$TITLE" ]];  then echo "ERROR: -t/--title is required" >&2; exit 1; fi
if [[ ! -f "$FILE" ]]; then echo "ERROR: file not found: $FILE" >&2; exit 1; fi

API="$BASE_URL/wiki/api/v2"

# Helper: build body value string from file
build_payload() {
  python3 - "$@" << 'PYEOF'
import sys, json

mode = sys.argv[1]
args = sys.argv[2:]

with open(args[-1]) as f:
    raw = f.read().strip()

# Accept either a bare ADF doc or a full page JSON with a 'body' key
try:
    parsed = json.loads(raw)
    if 'body' in parsed and 'type' in parsed['body']:
        body_obj = parsed['body']
    elif parsed.get('type') == 'doc':
        body_obj = parsed
    else:
        print("ERROR: unrecognised JSON structure — expected ADF doc or {body: adf}", file=sys.stderr)
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f"ERROR: invalid JSON in body file: {e}", file=sys.stderr)
    sys.exit(1)

body_value = json.dumps(body_obj)

if mode == 'create':
    space_id, parent_id, title = args[0], args[1], args[2]
    payload = {
        "spaceId": space_id,
        "parentId": parent_id,
        "status": "current",
        "title": title,
        "body": {"representation": "atlas_doc_format", "value": body_value}
    }
elif mode == 'update':
    page_id, version, title, msg = args[0], int(args[1]), args[2], args[3]
    payload = {
        "id": page_id,
        "status": "current",
        "title": title,
        "version": {"number": version, "message": msg},
        "body": {"representation": "atlas_doc_format", "value": body_value}
    }

print(json.dumps(payload))
PYEOF
}

case "$ACTION" in
  create)
    if [[ -z "$SPACE_ID" ]];  then echo "ERROR: -s/--space-id required for create" >&2; exit 1; fi
    if [[ -z "$PARENT_ID" ]]; then echo "ERROR: -P/--parent-id required for create" >&2; exit 1; fi

    PAYLOAD_FILE=$(mktemp /tmp/confluence_XXXX.json)
    build_payload create "$SPACE_ID" "$PARENT_ID" "$TITLE" "$FILE" > "$PAYLOAD_FILE"

    echo "Creating page: \"$TITLE\" in space $SPACE_ID under parent $PARENT_ID ..."
    curl -s -X POST "$API/pages" \
      -H "Authorization: $AUTH_HEADER" \
      -H "Content-Type: application/json" \
      --data "@$PAYLOAD_FILE" \
    | BASE_URL="$BASE_URL" python3 -c "
import os, sys, json
d = json.load(sys.stdin)
if 'errors' in d or 'statusCode' in d:
    print('ERROR:', json.dumps(d, indent=2))
else:
    webui = d.get('_links', {}).get('webui', '')
    base  = d.get('_links', {}).get('base', os.environ['BASE_URL'] + '/wiki')
    print(f\"Created: id={d.get('id')}  title={d.get('title')}\")
    print(f\"URL: {base}{webui}\")
"
    rm -f "$PAYLOAD_FILE"
    ;;

  update)
    if [[ -z "$PAGE_ID" ]]; then echo "ERROR: -p/--page-id required for update" >&2; exit 1; fi

    # Auto-fetch current version if not provided (v1 API returns version)
    if [[ -z "$VERSION" ]]; then
      echo "Fetching current version for page $PAGE_ID ..."
      VERSION=$(curl -s "$BASE_URL/wiki/rest/api/content/$PAGE_ID?expand=version" \
        -H "Authorization: $AUTH_HEADER" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['version']['number'])")
      echo "Current version: $VERSION — pushing version $((VERSION + 1))"
      VERSION=$((VERSION + 1))
    fi

    PAYLOAD_FILE=$(mktemp /tmp/confluence_XXXX.json)
    build_payload update "$PAGE_ID" "$VERSION" "$TITLE" "$MESSAGE" "$FILE" > "$PAYLOAD_FILE"

    echo "Updating page $PAGE_ID to v$VERSION: \"$TITLE\" ..."
    curl -s -X PUT "$API/pages/$PAGE_ID" \
      -H "Authorization: $AUTH_HEADER" \
      -H "Content-Type: application/json" \
      --data "@$PAYLOAD_FILE" \
    | BASE_URL="$BASE_URL" python3 -c "
import os, sys, json
d = json.load(sys.stdin)
if 'errors' in d or 'statusCode' in d:
    print('ERROR:', json.dumps(d, indent=2))
else:
    webui = d.get('_links', {}).get('webui', '')
    base  = d.get('_links', {}).get('base', os.environ['BASE_URL'] + '/wiki')
    v     = d.get('version', {}).get('number', '?')
    print(f\"Updated: id={d.get('id')}  title={d.get('title')}  version={v}\")
    print(f\"URL: {base}{webui}\")
"
    rm -f "$PAYLOAD_FILE"
    ;;

  *)
    echo "ERROR: unknown action '$ACTION' — use create or update" >&2
    exit 1
    ;;
esac
