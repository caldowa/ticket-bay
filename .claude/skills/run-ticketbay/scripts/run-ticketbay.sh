#!/usr/bin/env bash
# run-ticketbay.sh — install, start Postgres (host only), migrate, seed when empty. Does not start the dev server.
# Usage: scripts/run-ticketbay.sh [--reseed [--yes]]   (--reseed without --yes is a dry run)
set -euo pipefail

RESEED=0 YES=0
for a in "$@"; do
  case "$a" in
    --reseed) RESEED=1 ;;
    --yes) YES=1 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--reseed [--yes]]" >&2; exit 2 ;;
  esac
done
. "$(dirname "$0")/common.sh"
STATE_JS="$ROOT/.claude/skills/run-ticketbay/scripts/db-state.mjs"
step() { echo; echo "== $*"; }

step "1/4 deps ($(deps_state))"
if [ "$(deps_state)" != ok ]; then npm ci; else echo "up to date"; fi

step "2/4 database ($WHERE)"
if [ "$WHERE" = host ]; then
  npm run db:up
else
  tcp_open "$DB_HOST" "$DB_PORT" || { echo "box db not reachable at $DB_HOST:$DB_PORT: restart the box from the host (./box)" >&2; exit 1; }
  echo "box db reachable; db:up is not used in the box"
fi

step "3/4 migrate"
npm run db:migrate

step "4/4 demo data"
state=$(node "$STATE_JS")
echo "before: $state"
case "$state" in
  empty) npm run db:seed ;;
  data*)
    if [ "$RESEED" -eq 0 ]; then
      echo "keeping the existing data (to reseed: --reseed --yes, after approval)"
    elif [ "$YES" -eq 0 ]; then
      echo "DRY RUN: npm run db:seed would delete every account, session, API key and order ($state) and load the demo data."
      echo "Run again with --reseed --yes to do it."
    else
      npm run db:seed
    fi ;;
  *) echo "unexpected database state: $state" >&2; exit 1 ;;
esac
echo "after: $(node "$STATE_JS")"

echo
echo "Ready. Start the app: npm run dev   (port $APP_PORT; another port needs BETTER_AUTH_URL to match)"
echo "Logins (password ticketbay-demo): anna@ticketbay.test (customer), admin@ticketbay.test (admin)"
