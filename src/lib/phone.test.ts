import { describe, it, expect } from "vitest";
import { normalizeDzPhone } from "./phone";
describe("normalizeDzPhone", () => {
  it("accepts mobile with spaces", () => expect(normalizeDzPhone("0661 23 45 67")).toBe("0661234567"));
  it("converts +213", () => expect(normalizeDzPhone("+213 551234567")).toBe("0551234567"));
  it("empty clears", () => expect(normalizeDzPhone("  ")).toBe(""));
  it("rejects short", () => expect(normalizeDzPhone("06612")).toBeNull());
  it("rejects bad prefix mobile length", () => expect(normalizeDzPhone("0861234567")).toBeNull());
});
