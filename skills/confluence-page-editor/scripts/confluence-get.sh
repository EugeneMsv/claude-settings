#!/usr/bin/env bash
# confluence-get.sh — Fetch a Confluence page's ADF body + version via REST API
#
# Bypasses the Atlassian MCP's getConfluencePage tool, which returns its result
# through a token-capped tool-result envelope — pages of moderate size (roughly
# >90KB) blow that cap and get written to a tool-results/*.txt file instead of
# returned inline, which then has to be re-extracted with adf_tool.py fetch.
# This script hits the REST API directly via curl, so there's no such cap, AND
# it returns version.number in the same call — required for the optimistic-
# locking push flow (see confluence-push.sh's -v flag): capture the version
# here, at read time, and pass that same number (+1) explicitly to the later
# push, rather than letting push auto-fetch "current" version at push time
# (which silently overwrites any edit that landed in between).
#
# Flags:
#   -p, --page-id     page ID (required)
#   -o, --out         output path for the ADF body JSON (required)
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
# Output:
#   Writes the ADF body (a bare {"type":"doc",...} object — same shape
#   adf_tool.py's load() accepts) to the given -o path, and prints the page's
#   title, version.number, and lastModified-equivalent (createdAt of the
#   current version) to stdout for the caller to record.
#
# Examples:
#   confluence-get.sh -p 1375277721 -o .claude/confluence-page-editor/body_myrun.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${ATLASSIAN_TOKEN:-}" && -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

BASE_URL="${CONFLUENCE_BASE_URL:-}"
PAGE_ID=""
OUT=""

usage() {
  awk '/^# confluence-get/{p=1} p && /^[^#]/{exit} p{sub(/^# ?/,""); print}' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--page-id)  PAGE_ID="$2"; shift 2 ;;
    -o|--out)      OUT="$2";     shift 2 ;;
    -u|--base-url) BASE_URL="$2"; shift 2 ;;
    -h|--help)     usage 0 ;;
    *) echo "Unknown flag: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$PAGE_ID" ]]; then echo "ERROR: -p/--page-id is required" >&2; exit 1; fi
if [[ -z "$OUT" ]];     then echo "ERROR: -o/--out is required" >&2; exit 1; fi

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

API="$BASE_URL/wiki/api/v2"

mkdir -p "$(dirname "$OUT")"

RESPONSE_FILE=$(mktemp /tmp/confluence_get_XXXX.json)
trap 'rm -f "$RESPONSE_FILE"' EXIT

curl -s "$API/pages/$PAGE_ID?body-format=atlas_doc_format" \
  -H "Authorization: $AUTH_HEADER" \
  -o "$RESPONSE_FILE"

python3 - "$OUT" "$RESPONSE_FILE" << 'PYEOF'
import sys, json

out_path = sys.argv[1]
response_path = sys.argv[2]
with open(response_path) as f:
    raw = f.read()
d = json.loads(raw)

if "errors" in d or "statusCode" in d:
    print("ERROR:", json.dumps(d, indent=2), file=sys.stderr)
    sys.exit(1)

version = d.get("version", {}).get("number")
title = d.get("title")
created_at = d.get("version", {}).get("createdAt")

body_wrapper = d.get("body", {}).get("atlas_doc_format", {})
adf_value = body_wrapper.get("value")
if adf_value is None:
    print("ERROR: no body.atlas_doc_format.value in response — did you request "
          "a page id that exists, and does it have content?", file=sys.stderr)
    sys.exit(1)

# body.atlas_doc_format.value is a JSON-encoded STRING (double-encoded), not a
# nested object — must be parsed again to get the actual ADF doc.
adf_doc = json.loads(adf_value)

with open(out_path, "w") as f:
    json.dump(adf_doc, f)

print(f"title: {title}")
print(f"version: {version}")
print(f"version.createdAt: {created_at}")
print(f"top-level nodes: {len(adf_doc.get('content', []))}")
print(f"wrote: {out_path}")
print()
print(f"NEXT VERSION TO PUSH: {version + 1}")
PYEOF
