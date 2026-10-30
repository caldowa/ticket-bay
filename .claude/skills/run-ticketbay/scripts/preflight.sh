#!/usr/bin/env bash
# preflight.sh — reports what starting TicketBay needs here: host or box, Node, deps, Docker, database, port.
# Usage: scripts/preflight.sh   (read-only; exits 1 when something blocks the start)
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,3p' "$0"; exit 0 ;; esac
. "$(dirname "$0")/common.sh"
STATE_JS="$ROOT/.claude/skills/run-ticketbay/scripts/db-state.mjs"

BLOCK=0
echo "where: $WHERE (database $DB_HOST:$DB_PORT)"

node_major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo none)
if [ "$node_major" = "$(cat .nvmrc)" ]; then echo "node: $(node -v) ok"
else echo "node: $node_major, needs $(cat .nvmrc): run 'nvm use'"; BLOCK=1; fi

echo "deps: $(deps_state)"

if [ "$WHERE" = host ]; then
  if docker info >/dev/null 2>&1; then echo "docker: running"
  else echo "docker: not running: start Docker Desktop or the Docker daemon"; BLOCK=1; fi
fi

if tcp_open "$DB_HOST" "$DB_PORT"; then
  if [ "$(deps_state)" = missing ]; then echo "database: reachable (contents unknown until deps are installed)"
  else echo "database: $(node "$STATE_JS")"; fi
else
  if [ "$WHERE" = box ]; then echo "database: box db not reachable: restart the box (./box on the host)"; BLOCK=1
  else echo "database: not running (run-ticketbay.sh starts it)"; fi
fi

if tcp_open localhost "$APP_PORT"; then echo "port $APP_PORT: in use: TicketBay already running? run scripts/check-up.sh"
else echo "port $APP_PORT: free"; fi

exit "$BLOCK"
