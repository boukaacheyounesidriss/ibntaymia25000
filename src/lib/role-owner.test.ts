import { describe, expect, it } from "vitest";
import { guardOwnerAccount, isRoleOwnerIdentity, requireRoleOwner } from "./role-owner";

describe("exclusive role management", () => {
  it("recognizes only the existing account belonging to boukaachey@gmail.com", () => {
    expect(isRoleOwnerIdentity("178bd57a-486c-46a5-b395-4199bde4b4f3")).toBe(true);
    expect(isRoleOwnerIdentity("boukaachey@gmail.com")).toBe(false);
    expect(isRoleOwnerIdentity("another-admin")).toBe(false);
  });
  it("rejects even administrators when the authenticated database owner check fails", async () => {
    await expect(requireRoleOwner({ rpc: async () => ({ data: false, error: null }) })).rejects.toThrow();
    await expect(requireRoleOwner({ rpc: async () => ({ data: null, error: { message: "offline" } }) })).rejects.toThrow();
    await expect(requireRoleOwner({ rpc: async () => ({ data: true, error: null }) })).resolves.toBeUndefined();
  });
  it("protects the owner's account from every other caller", () => {
    expect(() => guardOwnerAccount("other-developer", "178bd57a-486c-46a5-b395-4199bde4b4f3")).toThrow();
    expect(() => guardOwnerAccount("178bd57a-486c-46a5-b395-4199bde4b4f3", "ordinary-user")).not.toThrow();
  });
});