// A first-time customer: no account yet. They create one, book a single
// ticket, and find it in "My orders" — the account they just made is the one
// the order belongs to. The customer is NOT in the seed: the account is made
// here, through the sign-up form, with an address no earlier attempt used.
import { test, expect } from "@playwright/test";
import { BOOKING_AT_MS, E2E_EVENTS, type E2EUser } from "./support/env";
import { bookThroughUI, setClock, signUp, ticketsLine, totalLine } from "./support/app";

test("a new customer signs up, books one ticket, and sees it in My orders", async ({ page, context }, testInfo) => {
  const ev = E2E_EVENTS.signUpAndBook;
  // A retry runs against the same server: a fresh address, so sign-up never meets "user already exists".
  const customer: E2EUser = { name: "Nora Newcomer", email: `newcomer-${testInfo.retry}-${Date.now()}@e2e.test` };
  await setClock(context, BOOKING_AT_MS);

  await signUp(page, customer, `/events/${ev}`);
  // Signed in straight away: the header shows the new account, not "Sign in".
  await expect(page.getByRole("button", { name: "Account" })).toContainText(customer.name);
  await expect(page.getByRole("link", { name: "Sign in" })).toHaveCount(0);

  await bookThroughUI(page, customer, ev, "1");
  // 1 x €50.00, plus the 3% service fee (€1.50).
  await expect(ticketsLine(page)).toHaveText("Tickets €50.00");
  await expect(totalLine(page)).toHaveText("Total paid €51.50");
  const orderNo = await page.getByRole("heading", { name: /^TB-\d{5}$/ }).textContent();

  // The customer finds the order the way they would: the header's "My orders" link.
  // (The order page's breadcrumb is a navigation with a "My orders" link too.)
  await page.getByRole("banner").getByRole("link", { name: "My orders" }).click();
  await page.waitForURL("/orders");
  await expect(page.getByRole("heading", { name: "My orders" })).toBeVisible();
  await expect(page.getByText(`1 order for ${customer.email}`), "a new account has this order and nothing else").toBeVisible();

  const rows = page.getByRole("row").filter({ has: page.getByRole("cell") });
  await expect(rows).toHaveCount(1);
  await expect(rows.getByRole("cell")).toHaveText([
    `${orderNo}22 May 2031, 20:00`,
    "First Timers Night",
    "Sun, 1 Jun 2031",
    "1",
    "€51.50",
    "Paid",
  ]);
});
