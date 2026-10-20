import { expect, test } from "@playwright/test";
import { USERS } from "./global-setup";
import { LOT_12, UNIT_4B, projectRows, signIn, signOut } from "./helpers";

// The brief's story, in the order it tells it. Serial: later tests depend on earlier state.
test.describe.configure({ mode: "serial" });

test("a signed-out visitor is sent to the sign-in page", async ({ page }) => {
  await page.goto("/projects");
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
});

test("a wrong password is refused with a visible message", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill(USERS.ana);
  await page.getByLabel("Password").fill("not-the-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByText("Invalid login credentials")).toBeVisible();
});

test("Ana sees Builder A's projects only, with Lot 12 stalled", async ({ page }) => {
  await signIn(page, USERS.ana);

  await expect(projectRows(page)).toHaveCount(5);
  await expect(page.getByRole("link", { name: "Lot 12" })).toBeVisible();
  await expect(page.getByText("Unit 4B")).toHaveCount(0);
  await expect(page.getByText("Builder B")).toHaveCount(0);

  const lot12 = projectRows(page).filter({ hasText: "Lot 12" });
  await expect(lot12.getByText("Stalled")).toBeVisible();
  await expect(projectRows(page).filter({ hasText: "Lot 14" }).getByText("Stalled")).toHaveCount(0);

  // Not staff: the detector page is a courtesy message, and a Builder B project is not found.
  await page.goto("/detector");
  await expect(page.getByText("This page is for Reverie3D staff.")).toBeVisible();
  await page.goto(`/projects/${UNIT_4B}`);
  await expect(page.getByText("This page could not be found.")).toBeVisible();

  await page.goto("/projects");
  await signOut(page);
});

test("staff see every builder's projects and run the detector twice without duplicates", async ({ page }) => {
  await signIn(page, USERS.staff);

  await expect(projectRows(page)).toHaveCount(9);
  await expect(page.getByRole("columnheader", { name: "Builder", exact: true })).toBeVisible();
  for (const name of ["Lot 12", "Unit 4B", "Unit 7C"]) {
    await expect(projectRows(page).filter({ hasText: name }).getByText("Stalled")).toBeVisible();
  }

  await page.goto("/detector");
  await expect(page.getByText("No runs yet")).toBeVisible();

  await page.getByRole("button", { name: "Run now" }).click();
  const runs = page.locator("table tbody tr");
  await expect(runs).toHaveCount(1);
  await expect(runs.nth(0)).toContainText("succeeded");
  // Stalled | New stalls | Alerts sent
  await expect(runs.nth(0).locator("td").nth(4)).toHaveText("3");
  await expect(runs.nth(0).locator("td").nth(5)).toHaveText("3");
  await expect(runs.nth(0).locator("td").nth(6)).toHaveText("3");

  await page.getByRole("button", { name: "Run now" }).click();
  await expect(runs).toHaveCount(2);
  await expect(runs.nth(0).locator("td").nth(4)).toHaveText("3");
  await expect(runs.nth(0).locator("td").nth(5)).toHaveText("0");
  await expect(runs.nth(0).locator("td").nth(6)).toHaveText("0");

  // Staff get no stall alerts.
  await page.goto("/alerts");
  await expect(page.getByText("No alerts.")).toBeVisible();
  await signOut(page);
});

test("Bruno gets his two alerts and can mark one read, and only read", async ({ page }) => {
  await signIn(page, USERS.bruno);
  await expect(projectRows(page)).toHaveCount(4);
  await expect(page.getByRole("link", { name: /^Alerts/ })).toContainText("2");

  await page.goto("/alerts");
  const items = page.locator("main li");
  await expect(items).toHaveCount(2);
  await expect(page.getByText("Unit 4B has had no builder activity for 8 days. 5 slots are still empty.")).toBeVisible();
  await expect(page.getByText("Unit 7C has had no builder activity for 9 days. 3 slots are still empty.")).toBeVisible();

  await items.filter({ hasText: "Unit 4B" }).getByRole("button", { name: "Mark as read" }).click();
  await expect(items.filter({ hasText: "Unit 4B" }).getByText(/Read /)).toBeVisible();
  await expect(page.getByRole("button", { name: "Mark as read" })).toHaveCount(1);
  await expect(page.getByRole("link", { name: /^Alerts/ })).toContainText("1");
  await signOut(page);
});

test("Mia, a Builder A member but not an admin, got no alert", async ({ page }) => {
  await signIn(page, USERS.mia);
  await expect(projectRows(page)).toHaveCount(5);
  await page.goto("/alerts");
  await expect(page.getByText("No alerts.")).toBeVisible();
  await signOut(page);
});

test("Ana has one alert, and picking a product clears the stalled badge", async ({ page }) => {
  await signIn(page, USERS.ana);
  await expect(page.getByRole("link", { name: /^Alerts/ })).toContainText("1");

  await page.goto("/alerts");
  await expect(page.getByText("Lot 12 has had no builder activity for 7 days. 3 slots are still empty.")).toBeVisible();

  await page.goto(`/projects/${LOT_12}`);
  await expect(page.getByRole("heading", { name: "Lot 12" })).toBeVisible();
  await expect(page.getByText("Stalled")).toBeVisible();

  const laundry = page.locator("li").filter({ hasText: "Floor Tile" }).filter({ hasText: "empty" }).first();
  await laundry.getByRole("textbox").fill("Honed Marble 12x24");
  await laundry.getByRole("button", { name: "Set" }).click();

  const picked = (value: string) => page.locator(`input[name="product_name"][value="${value}"]`);
  await expect(picked("Honed Marble 12x24")).toBeVisible();
  await expect(page.getByText("Stalled")).toHaveCount(0);
  await expect(page.getByText("6 of 8").first()).toBeVisible();

  // Change it, then clear it.
  const row = page.locator("li").filter({ has: picked("Honed Marble 12x24") });
  await row.getByRole("textbox").fill("Honed Marble 24x24");
  await row.getByRole("button", { name: "Change" }).click();
  await expect(picked("Honed Marble 24x24")).toBeVisible();

  await page.locator("li").filter({ has: picked("Honed Marble 24x24") }).getByRole("button", { name: "Clear" }).click();
  await expect(picked("Honed Marble 24x24")).toHaveCount(0);
  await expect(page.getByText("5 of 8").first()).toBeVisible();

  // Clearing is builder activity too, so Lot 12 stays un-stalled.
  await page.goto("/projects");
  await expect(projectRows(page).filter({ hasText: "Lot 12" }).getByText("Stalled")).toHaveCount(0);
  await signOut(page);
});

test("an empty product name is refused", async ({ page }) => {
  await signIn(page, USERS.ana);
  await page.goto(`/projects/${LOT_12}`);
  const empty = page.locator("li").filter({ hasText: "empty" }).first();
  await empty.getByRole("button", { name: "Set" }).click();
  await expect(page.getByText("Enter a product name.")).toBeVisible();
  await signOut(page);
});
