import { describe, it, expect } from "vitest";
import { safeLink } from "./teacher-hub";
describe("safeLink", () => {
  it("accepts https", () => expect(safeLink("https://x.dz/a")).toBe("https://x.dz/a"));
  it("rejects javascript links", () => expect(safeLink("javascript:alert(1)")).toBeNull());
});
