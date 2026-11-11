import { describe, it, expect } from "vitest";
import { pinProblem } from "@/components/TeacherPinCard";

describe("teacher attendance PIN rules", () => {
  it("rejects fewer than 4 digits", () => expect(pinProblem("123")).not.toBeNull());
  it("rejects more than 6 digits", () => expect(pinProblem("1234567")).not.toBeNull());
  it("rejects repeated digits", () => expect(pinProblem("1111")).not.toBeNull());
  it("rejects simple sequences", () => expect(pinProblem("1234")).not.toBeNull());
  it("accepts a normal 5-digit PIN", () => expect(pinProblem("40719")).toBeNull());
});
