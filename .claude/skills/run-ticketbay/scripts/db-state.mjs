#!/usr/bin/env node
// db-state.mjs — prints the state of the TicketBay database in one line:
//   unreachable | unmigrated | empty | data users=<n> orders=<n> events=<n>
// Reads DATABASE_URL like scripts/local-env.ts. Read-only. Run from the repo root.
import fs from "node:fs";
import pg from "pg";

for (const f of [".env", ".env.example"]) if (fs.existsSync(f)) process.loadEnvFile(f);
const client = new pg.Client({ connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 3000 });
try {
  await client.connect();
} catch {
  console.log("unreachable");
  process.exit(0);
}
try {
  const { rows } = await client.query(`select to_regclass('public.orders') is not null and to_regclass('public."user"') is not null as ok`);
  if (!rows[0].ok) {
    console.log("unmigrated");
  } else {
    const c = (await client.query(`select (select count(*) from "user")::int u, (select count(*) from orders)::int o, (select count(*) from events)::int e`)).rows[0];
    console.log(c.u + c.o + c.e === 0 ? "empty" : `data users=${c.u} orders=${c.o} events=${c.e}`);
  }
} finally {
  await client.end();
}
