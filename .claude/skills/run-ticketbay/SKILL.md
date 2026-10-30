---
name: run-ticketbay
description: "Run TicketBay locally: database, demo data, logins. Use when the user says run TicketBay, start the app, spin it up, set it up from scratch or a fresh clone, reset the demo data, reseed, what's the login or admin password, or sign-in doesn't work locally. Works on the host (Docker Postgres) and in the box (its own db): installs, migrates, seeds an empty database, starts npm run dev and checks the storefront, the API and both demo logins. Never reseeds a database that has data without approval: the seed wipes every account, API key and order."
---

# Run TicketBay

From a fresh clone or a stopped app to http://localhost:3000 with demo data and two working logins. Run every script from the repo root.

## Steps

1. **Check the machine.** Run `.claude/skills/run-ticketbay/scripts/preflight.sh`. Done when it exits 0. On exit 1, fix the line it names (`nvm use`, start Docker, restart the box from the host) and run it again. If it says `port 3000: in use`, go to step 5 first: the app may already be up.
2. **Decide on reseeding.** Read the `database:` line. `empty`, `unmigrated` or `not running` → no decision, step 3 seeds. `data users=…` and the user asked to reset or reseed → show what `run-ticketbay.sh --reseed` prints (the dry run) and ask. Anything else → keep the data. Done when you know whether to pass `--reseed --yes`.
3. **Prepare.** Run `.claude/skills/run-ticketbay/scripts/run-ticketbay.sh`, or with `--reseed --yes` only after the user said yes in step 2. It runs `npm ci` when needed, `npm run db:up` on the host only, `npm run db:migrate`, and `npm run db:seed` when the database is empty. Done when it prints `Ready.` and `after: data users=2 …` (after a fresh seed: 2 users, 8 events, ~300 orders).
4. **Start the app.** Run `npm run dev` as a background command; it keeps running. Another port: `PORT=3100 BETTER_AUTH_URL=http://localhost:3100 npm run dev`. Done when its output shows `Ready in`.
5. **Check it works.** Run `.claude/skills/run-ticketbay/scripts/check-up.sh [port]`. The first request compiles pages and takes up to a minute. Done when every line says `ok`.
6. **Report.** Give the user exactly this:

   | | |
   |---|---|
   | Storefront | http://localhost:3000 |
   | Dashboard | http://localhost:3000/admin |
   | Customer | `anna@ticketbay.test` / `ticketbay-demo` (has orders under **My orders**) |
   | Admin | `admin@ticketbay.test` / `ticketbay-demo` |

   Add one line: stop with Ctrl-C in the dev terminal (or stop the background task); `npm run db:down` stops the host database and keeps its data.

## Gotchas

- **Reseeding is destructive.** `npm run db:seed` TRUNCATEs `user` (cascading to sessions and API keys), `orders`, `events` and `discount_codes`. API keys made under Settings → Developers are gone after it. Never run it on a database with data without the user's yes.
- **Never run `docker compose down -v`.** It deletes the `ticketbay-pg` volume. `npm run db:down` is the stop command.
- **In the box, never run `npm run db:up`** and never mount the host's Docker socket. The box has its own Postgres at `db:5432` (set in `.devcontainer/compose.yaml`), not published to the host.
- **DATABASE_URL points only at the local or box Postgres** (`localhost` or `db`). The scripts refuse any other host. The values in `.env.example` are local-only; never put real secrets in `.env`.
- **Sign-in 403 "Invalid origin"** means the browser origin is not `BETTER_AUTH_URL`. Open `http://localhost:<port>`, not `http://127.0.0.1:<port>`. On another port, set `BETTER_AUTH_URL` to match (the box does this from `BOX_PORT`).
- **Port 5432 taken on the host** by another Postgres: put `POSTGRES_PORT=5433` in `.env` and the same port in its `DATABASE_URL`.
- **Seed dates move.** The seed is deterministic relative to the current hour, so event dates and refund windows shift on every reseed. Order numbers restart at TB-00001.
- **curl by hand needs the full URL.** The Bash guard hook (`.claude/hooks/guard-network.sh`) blocks `curl localhost:3000`; `curl http://localhost:3000/…` passes. It also blocks command lines that start with `set` or `env`.
- **Tests do not need this.** `npm run test:unit` runs without a database; the Postgres test lanes make their own databases.

Last verified: 2026-10-30 with Claude Code in the box (from an empty node_modules and database: preflight, setup, reseed dry run, check-up 5/5 ok; triggers 3/3, near-miss quiet). The host path is not run yet.
