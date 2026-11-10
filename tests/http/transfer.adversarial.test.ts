// Adversarial checks of POST /api/v1/orders/{id}/transfer against
// docs/specs/ticket-transfer-4.3-start.md, through the real route handlers.
// tests/http/client.ts does not route .../transfer (it falls to the catch-all),
// so the transfer route module is called directly, as Next.js would call it.
import { describe, it, expect, vi, beforeAll, afterAll } from "vitest";
import type { Auth } from "../../src/auth/auth";
import { getOrder } from "../../src/db/orders-repo";
import { createFakeStripe } from "../../src/payments";
import { customer, makeAuth, useCleanAccounts, type Customer } from "../integration/accounts";
import { useTestDatabase } from "../integration/database";
import { DAY, HOUR, NOW, venue } from "../integration/fixtures";
import { bearer, call, loadRoutes, quietRefusedKeyLogs, read, request } from "./client";

const wiring = vi.hoisted(() => ({ auth: undefined as unknown, db: undefined as unknown, payments: undefined as unknown }));
vi.mock("@/lib/auth", () => ({ appBaseURL: () => "http://localhost:3000", getAuth: () => wiring.auth }));
vi.mock("@/src/db/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../src/db/client")>()),
  getDb: () => wiring.db,
}));
vi.mock("@/src/payments", async () => ({ ...(await import("../../src/payments")), getPayments: () => wiring.payments }));

const t = useTestDatabase();
useCleanAccounts(t);
quietRefusedKeyLogs();

let auth: Auth;
type Handler = (r: Request, ctx: { params: Promise<{ id: string }> }) => Promise<Response>;
let transferPOST: Handler;

beforeAll(async () => {
  process.env.TICKETBAY_TEST_CLOCK = "1";
  auth = makeAuth(t.db);
  wiring.auth = auth;
  wiring.db = t.db;
  wiring.payments = createFakeStripe("sk_test_integration");
  await loadRoutes();
  transferPOST = (await import("../../app/api/v1/orders/[id]/transfer/route")).POST as unknown as Handler;
});

afterAll(() => {
  delete process.env.TICKETBAY_TEST_CLOCK;
});

const book = async (c: Customer, eventId: string, nowMs = NOW) => {
  const r = await call({ method: "POST", path: "/api/v1/orders", json: { eventId, tickets: 2 }, headers: { ...bearer(c.key), "idempotency-key": `k-${Math.random()}` }, nowMs });
  expect(r.status, r.text).toBe(201);
  return r.body.order as { id: number };
};

const transfer = async (id: number, c: Customer, email: string, nowMs = NOW) => {
  const req = request({ method: "POST", path: `/api/v1/orders/${id}/transfer`, json: { email }, headers: bearer(c.key), nowMs });
  return read(await transferPOST(req, { params: Promise.resolve({ id: String(id) }) }));
};

describe("POST /api/v1/orders/{id}/transfer", () => {
  it("criterion 3: refuses a transfer when the request's clock is after the event start", async () => {
    const anna = await customer(auth, "Anna");
    const bela = await customer(auth, "Bela");
    await venue(t.db, { id: "rockfest", startsAtMs: NOW + 10 * DAY });
    const o = await book(anna, "rockfest");

    const r = await transfer(o.id, anna, bela.email, NOW + 10 * DAY + HOUR);

    expect(r.status, r.text).toBe(422);
    expect((await getOrder(t.db, o.id))!.holderId).toBeNull();
  });

  it("criterion 5: after a transfer, the old owner's POST /orders/{id}/cancel is a 404 and refunds nothing", async () => {
    const anna = await customer(auth, "Anna");
    const bela = await customer(auth, "Bela");
    await venue(t.db, { id: "rockfest", startsAtMs: NOW + 10 * DAY });
    const o = await book(anna, "rockfest");
    expect((await transfer(o.id, anna, bela.email)).status).toBe(200);

    const r = await call({ method: "POST", path: `/api/v1/orders/${o.id}/cancel`, headers: bearer(anna.key), nowMs: NOW });

    expect(r).toMatchObject({ status: 404, body: { error: "Order not found." } });
    expect((await getOrder(t.db, o.id))!.status).toBe("paid");
  });
});
