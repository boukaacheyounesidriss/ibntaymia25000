import { expect, it } from "vitest";
import { accountIsDisabled } from "./account-status";

it("shows a reactivated account as enabled when its ban has expired", () => {
  expect(accountIsDisabled("2026-11-13T12:00:00Z", Date.parse("2026-11-14T12:00:00Z"))).toBe(false);
});
it("shows a currently banned account as disabled", () => {
  expect(accountIsDisabled("2026-11-15T12:00:00Z", Date.parse("2026-11-14T12:00:00Z"))).toBe(true);
});