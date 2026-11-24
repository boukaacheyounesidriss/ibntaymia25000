import { describe, it, expect } from "vitest";
import { normalizeClaimCode, CLAIM_CODE_RE } from "./pending-claim";
describe("claim codes", () => {
  it("normalizes typed codes", () => {
    expect(normalizeClaimCode("taym abcd 2345")).toBe("TAYM-ABCD-2345");
    expect(normalizeClaimCode("abcd2345")).toBe("TAYM-ABCD-2345");
    expect(CLAIM_CODE_RE.test(normalizeClaimCode("TAYM-ABCD-2345"))).toBe(true);
  });
});
