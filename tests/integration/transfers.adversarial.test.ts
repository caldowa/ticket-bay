// Adversarial checks of ticket transfer against docs/specs/ticket-transfer-4.3-start.md,
// at the service layer (the functions the app's actions, REST API and MCP call),
// real Postgres, real Better Auth accounts, the fake Stripe.
import { describe, it, expect } from "vitest";
import { getOrder, listOrdersByUser } from "../../src/db/orders-repo";
import { createFakeStripe } from "../../src/payments";
import { cancelOwnOrder, placeOrder, type Deps } from "../../src/services/orders";
import { transferOrder } from "../../src/services/transfers";
import { useTestDatabase } from "./database";
import { DAY, HOUR, NOW, venue } from "./fixtures";
import { customer, makeAuth, useCleanAccounts } from "./accounts";

const t = useTestDatabase();
useCleanAccounts(t);

let keys = 0;
function deps(nowMs = NOW): Deps {
  return { db: t.db, payments: createFakeStripe("sk_test_integration"), nowMs };
}

async function people() {
  const auth = makeAuth(t.db);
  return { anna: await customer(auth, "Anna"), bela: await customer(auth, "Bela"), cili: await customer(auth, "Cili") };
}

async function annasOrder(annaId: string, annaEmail: string, over: Parameters<typeof venue>[1] = {}, bookedAt = NOW) {
  const ev = await venue(t.db, over);
  const { order } = await placeOrder(deps(bookedAt), { eventId: ev.id, quantity: 2, email: annaEmail, name: "Anna", idempotencyKey: `adv-${++keys}`, userId: annaId });
  return { ev, order };
}

describe("criterion 3: a transfer is possible only before the event starts", () => {
  it("refuses to transfer an order whose event started an hour ago (real wall clock)", async () => {
    const { anna, bela } = await people();
    // The event started an hour ago in real time, so no clock — test or wall — can call it "before the event".
    const startsAtMs = Date.now() - HOUR;
    const { order } = await annasOrder(anna.id, anna.email, { startsAtMs, createdAtMs: startsAtMs - 30 * DAY }, startsAtMs - DAY);

    await expect(transferOrder({ db: t.db }, anna.id, order.id, bela.email)).rejects.toThrow();
    expect((await getOrder(t.db, order.id))!.holderId).toBeNull();
  });
});

describe("criterion 5: a transferred ticket can't be refunded by the old owner", () => {
  it("refuses the old owner's cancel-and-refund after the transfer", async () => {
    const { anna, bela } = await people();
    const { order } = await annasOrder(anna.id, anna.email);
    await transferOrder({ db: t.db }, anna.id, order.id, bela.email);

    await expect(cancelOwnOrder(deps(), anna.id, order.id)).rejects.toThrow("Order not found.");
    const after = (await getOrder(t.db, order.id))!;
    expect(after.status).toBe("paid");
    expect(after.holderId).toBe(bela.id);
  });
});

describe("cases the criteria do not decide", () => {
  it("[undecided] the friend who now holds the order can cancel it (the order page offers them the Cancel form)", async () => {
    const { anna, bela } = await people();
    const { order } = await annasOrder(anna.id, anna.email);
    await transferOrder({ db: t.db }, anna.id, order.id, bela.email);

    // The order page (holderOf === bela) shows Bela the refund preview and Cancel button.
    const r = await cancelOwnOrder(deps(), bela.id, order.id);
    expect(r.order.status).toBe("refunded");
  });

  it("[undecided, criterion 1] a friend who received the tickets cannot pass them on — only the order's owner transfers", async () => {
    const { anna, bela, cili } = await people();
    const { order } = await annasOrder(anna.id, anna.email);
    await transferOrder({ db: t.db }, anna.id, order.id, bela.email);

    await expect(transferOrder({ db: t.db }, bela.id, order.id, cili.email)).rejects.toThrow("Order not found.");
  });

  it("[undecided] two transfers of the same order at the same time: at most one wins, and each answer tells the truth", async () => {
    const { anna, bela, cili } = await people();
    const { order } = await annasOrder(anna.id, anna.email);

    const results = await Promise.allSettled([
      transferOrder({ db: t.db }, anna.id, order.id, bela.email),
      transferOrder({ db: t.db }, anna.id, order.id, cili.email),
    ]);
    const final = (await getOrder(t.db, order.id))!;
    const won = results.filter((r) => r.status === "fulfilled");
    expect(won).toHaveLength(1);
    for (const r of won) expect(r.value.holderId).toBe(final.holderId);
    expect((await listOrdersByUser(t.db, bela.id)).length + (await listOrdersByUser(t.db, cili.id)).length).toBe(1);
  });
});
