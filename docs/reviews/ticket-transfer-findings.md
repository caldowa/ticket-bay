# Ticket transfer: adversarial review findings

- Change reviewed: `git diff main...lesson/4.3-start`
- Acceptance criteria: `docs/specs/ticket-transfer-4.3-start.md`
- Repo rules: `AGENTS.md`
- Method: the adversarial-tester skill, run by a separate agent with its own context
- Date: 2026-11-10

**Verdict: don't merge.** The change breaks acceptance criteria 3 and 5, and failing tests prove both. An order can still be transferred after its event has started, and the old owner can still refund an order they have given away.

## Caused by this change (blocks the merge)

### 1. [PROVED] A transfer works after the event has started (criterion 3)

- **Tests:**
  - `tests/integration/transfers.adversarial.test.ts` › "refuses to transfer an order whose event started an hour ago (real wall clock)"
  - `tests/http/transfer.adversarial.test.ts` › "criterion 3: refuses a transfer when the request's clock is after the event start"
- **Input:** a paid order whose event started 1h ago, or an API request whose clock is 1h after the event start.
- **Expected:** the transfer is refused with a 422 and `holderId` stays null.
- **Actual:** the transfer succeeds and the API returns 200.
- **Cause:** `src/services/transfers.ts:16-30` takes no clock and never reads the event. The order page also shows the Transfer form for any paid order, even after the event has started (`app/(public)/orders/[id]/page.tsx:131`).
- **Damage:** anyone can pass on or resell tickets during or after the event, which the spec forbids.

### 2. [PROVED] The old owner can still refund a transferred order (criterion 5)

- **Tests:**
  - `tests/integration/transfers.adversarial.test.ts` › "refuses the old owner's cancel-and-refund after the transfer"
  - `tests/http/transfer.adversarial.test.ts` › "criterion 5: after a transfer, the old owner's POST /orders/{id}/cancel is a 404 and refunds nothing"
- **Input:** Anna transfers her order to Bela, then calls `cancelOwnOrder(anna.id, id)` or `POST /api/v1/orders/{id}/cancel` with her own key.
- **Expected:** 404 "Order not found.", and the order stays paid.
- **Actual:** the call returns 200, the order is refunded and the money goes back to Anna.
- **Cause:** `cancelOwnOrder` (`src/services/orders.ts:338`) still checks `found.userId`, and this change did not update it. The MCP `refund_order` tool (`src/mcp/tools.ts:410`) and `cancelOrderAction` both call it, so they have the same hole.
- **Damage:** Anna can give or sell the tickets and then refund them. Bela's tickets are voided and Anna keeps the money.

### 3. [REASONED] The new holder is shown a Cancel button that always fails

- **Where:** `app/(public)/orders/[id]/page.tsx:31` and the cancellation section after it, compared with `src/services/orders.ts:338`.
- **Why:** the page lets the holder in (`holderOf`) and shows them the refund preview and the Cancel form. The cancel path only accepts the person who booked the order.
- **Supporting test:** `tests/integration/transfers.adversarial.test.ts` › "[undecided] the friend who now holds the order can cancel it" fails with `OrderError: Order not found.`
- **Not proved because:** the spec doesn't say whether the holder may cancel.
- **Check:** decide who may cancel a transferred order and who gets the money. Swapping in `holderOf` alone would let Bela refund money onto Anna's card.

### 4. [REASONED] A friend who received tickets can transfer them on again (criterion 1)

- **Where:** `src/services/transfers.ts:19`, which checks `holderOf(order) !== userId`.
- **Supporting test:** `tests/integration/transfers.adversarial.test.ts` › "[undecided, criterion 1] a friend who received the tickets cannot pass them on". Bela's transfer to Cili succeeds.
- **Not proved because:** it depends on whether "owner" in criterion 1 means the person who booked the order or the current holder.
- **Check:** decide which one "owner" means. If it means the booker, the current code lets transfers chain without limit.

### 5. [REASONED] Two transfers at the same moment both succeed, and the last one wins

- **Where:** `src/services/transfers.ts:18-29` and `setHolder` at `src/db/orders-repo.ts:62-68`.
- **Why:** the ownership check happens when the order is read. The update only filters on `id` and `status = 'paid'`, with no row lock and no condition on `holder_id`.
- **Supporting test:** `tests/integration/transfers.adversarial.test.ts` › "[undecided] two transfers of the same order at the same time". Two parallel transfers by Anna, to Bela and to Cili, both succeed.
- **Not proved because:** "at most one wins" is the agent's own expectation, not a criterion. The worse case needs exact timing: Anna's stale transfer lands after Bela already holds the order and has passed it on, so Anna overwrites a holding she no longer owns.
- **Check:** add `holder_id IS NOT DISTINCT FROM <expected holder>` to the `setHolder` WHERE clause, or lock the row.

### 6. [REASONED] The transfer form tells anyone whether an email has an account

- **Where:** `src/services/transfers.ts:25`, which answers "No TicketBay account uses this email…" (422 on the API).
- **Why:** anyone with one paid order or an API key with write access can check which emails have accounts, with no rate limit.
- **Not proved because:** criterion 2 requires the friend to have an account but doesn't say how the error should read. This is a privacy decision.
- **Check:** decide whether this answer is acceptable.

## Found, not caused by this change (never blocks)

None. The new tests can't run on `main`, because `src/services/transfers.ts` doesn't exist there. Finding 2 sits in old code, but it only becomes a bug because this change adds a holder.

## Hunted, nothing broke

- **Input checks:**
  - order-ID parsing: `NaN` in the form action, and `OrderIdParam` in the API
  - emails: trimming, letter case and the format check
  - transferring to yourself, or back to the booker
- **Status checks:** refunded orders and orders on cancelled events are refused.
- **Order lists:** the My orders page and the MCP `my_orders` tool follow the new holder rule consistently.
- **The rest:** API errors map to 404 and 422 as designed, and the migration's foreign key matches the existing `user_id` one.

## Test run and gaps

The existing suites are green: 277 passed and 2 skipped, against real Postgres in Docker. The only failures are the 7 new adversarial tests.

Gaps:

- The branch's own tests cover only happy paths.
- `tests/http/client.ts` was never updated to route `/orders/{id}/transfer`, so the HTTP adversarial test calls the route module directly.
- The Playwright e2e test (`e2e/transfer.spec.ts`) was not run, because it needs the app server.

The breaking tests are in the working tree, uncommitted:

- `tests/integration/transfers.adversarial.test.ts`
- `tests/http/transfer.adversarial.test.ts`
