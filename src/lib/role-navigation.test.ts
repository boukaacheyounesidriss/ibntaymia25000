import { describe, expect, it } from "vitest";
import { canAccess, defaultLandingFor } from "./nav-config";

describe("owner-only permissions page", () => {
  it("blocks non-owner administrators and developers even at a manually typed URL", () => {
    expect(canAccess("/dashboard/permissions", ["admin", "developer"], "another-user")).toBe(false);
    expect(canAccess("/dashboard/permissions/", ["student"], "another-user")).toBe(false);
    expect(canAccess("/dashboard/permissions", ["admin"], "178bd57a-486c-46a5-b395-4199bde4b4f3")).toBe(true);
  });
});

describe("digital advisor navigation", () => {
  it("can reach supervisor operations with the actual assigned role", () => {
    expect(canAccess("/dashboard/absence-report", ["digital_advisor"])).toBe(true);
    expect(canAccess("/dashboard/claim-codes", ["digital_advisor"])).toBe(true);
    expect(defaultLandingFor(["digital_advisor"])).toBe("/dashboard/supervisor");
  });
  it("does not gain owner role management or raw technical access", () => {
    expect(canAccess("/dashboard/permissions", ["digital_advisor"], "another-user")).toBe(false);
    expect(canAccess("/dashboard/data", ["digital_advisor"])).toBe(false);
  });
});
