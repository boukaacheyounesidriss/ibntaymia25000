import { describe, expect, it } from "vitest";
import { canAccess } from "./nav-config";

describe("owner-only permissions page", () => {
  it("blocks non-owner administrators and developers even at a manually typed URL", () => {
    expect(canAccess("/dashboard/permissions", ["admin", "developer"], "another-user")).toBe(false);
    expect(canAccess("/dashboard/permissions/", ["student"], "another-user")).toBe(false);
    expect(canAccess("/dashboard/permissions", ["admin"], "178bd57a-486c-46a5-b395-4199bde4b4f3")).toBe(true);
  });
});