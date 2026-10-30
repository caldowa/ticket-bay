#!/usr/bin/env bash
# common.sh — sourced by the other scripts: repo root, where we run, the database address.
# Not meant to be run on its own.

ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$ROOT"
grep -q '"name": "ticketbay"' package.json || { echo "not the TicketBay repo: $ROOT" >&2; exit 1; }

# DATABASE_URL the way scripts/local-env.ts resolves it: environment, then .env, then .env.example.
db_url() {
  if [ -n "${DATABASE_URL:-}" ]; then echo "$DATABASE_URL"; return; fi
  local f
  for f in .env .env.example; do
    if [ -f "$f" ] && grep -q '^DATABASE_URL=' "$f"; then grep '^DATABASE_URL=' "$f" | tail -1 | cut -d= -f2-; return; fi
  done
}
DB_URL=$(db_url)
DB_HOSTPORT=${DB_URL#*@}; DB_HOSTPORT=${DB_HOSTPORT%%/*}
DB_HOST=${DB_HOSTPORT%%:*}
DB_PORT=${DB_HOSTPORT##*:}; [ "$DB_PORT" = "$DB_HOSTPORT" ] && DB_PORT=5432

# The box sets DATABASE_URL to db:5432 (.devcontainer/compose.yaml); anywhere else is the host.
if [ "$DB_HOST" = "db" ]; then WHERE=box; else WHERE=host; fi
case "$DB_HOST" in
  db|localhost|127.0.0.1) ;;
  *) echo "DATABASE_URL points at $DB_HOST, not the local or box Postgres: refusing" >&2; exit 1 ;;
esac

APP_PORT=${PORT:-3000}

tcp_open() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

deps_state() {
  if [ ! -f node_modules/.package-lock.json ]; then echo missing
  elif [ package-lock.json -nt node_modules/.package-lock.json ]; then echo stale
  else echo ok; fi
}
