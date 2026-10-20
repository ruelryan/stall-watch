import { expect, type Page } from "@playwright/test";
import { E2E_PASSWORD } from "./global-setup";

export const LOT_12 = "00000000-0000-0000-0000-00000000a012";
export const UNIT_4B = "00000000-0000-0000-0000-00000000b04b";

export async function signIn(page: Page, email: string) {
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(E2E_PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL("**/projects");
  await expect(page.getByRole("heading", { name: "Projects" })).toBeVisible();
}

export async function signOut(page: Page) {
  await page.getByRole("button", { name: "Sign out" }).click();
  await page.waitForURL("**/login");
}

export function projectRows(page: Page) {
  return page.locator("table tbody tr");
}
