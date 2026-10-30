#!/usr/bin/env bash
# check-up.sh — checks the running app: storefront, the events API, and both demo logins.
# Usage: scripts/check-up.sh [port]   (default $PORT or 3000; read-only apart from two sign-in sessions)
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,3p' "$0"; exit 0 ;; esac
PORT_ARG=${1:-${PORT:-3000}}
[[ "$PORT_ARG" =~ ^[0-9]+$ ]] || { echo "usage: $0 [port]" >&2; exit 2; }
BASE="http://localhost:$PORT_ARG"
FAIL=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; FAIL=1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 90 "$BASE/" || true)
if [ "$code" = 200 ]; then ok "storefront $BASE/ (200)"
else bad "storefront $BASE/ answered '$code': is npm run dev running on port $PORT_ARG?"; exit 1; fi

n=$(curl -s --max-time 60 "$BASE/api/v1/events" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).events.length)}catch{console.log("?")}})')
if [ "$n" = 8 ]; then ok "GET /api/v1/events: 8 events"
else bad "GET /api/v1/events: $n events, expected 8 (not seeded? run run-ticketbay.sh)"; fi

for who in anna admin; do
  code=$(curl -s -o "$TMP/$who.body" -w '%{http_code}' --max-time 60 -c "$TMP/$who.jar" \
    -H "Origin: $BASE" -H 'content-type: application/json' \
    -d "{\"email\":\"$who@ticketbay.test\",\"password\":\"ticketbay-demo\"}" "$BASE/api/auth/sign-in/email" || true)
  case "$code" in
    200) ok "sign-in $who@ticketbay.test" ;;
    403) bad "sign-in $who: 403 $(head -c 200 "$TMP/$who.body"): BETTER_AUTH_URL must be $BASE" ;;
    401) bad "sign-in $who: 401, account missing or password changed (reseed restores it)" ;;
    *)   bad "sign-in $who: HTTP $code $(head -c 200 "$TMP/$who.body")" ;;
  esac
done

# "Olivia Admin" is the seeded admin's name, shown in the admin top bar.
page=$(curl -s --max-time 90 -b "$TMP/admin.jar" "$BASE/admin" || true)
if grep -q 'Admins only' <<<"$page"; then bad "/admin: admin@ticketbay.test is not an admin (reseed restores it)"
elif grep -q 'Olivia Admin' <<<"$page"; then ok "/admin renders the dashboard for admin@ticketbay.test"
else bad "/admin did not render the dashboard"; fi

exit "$FAIL"
