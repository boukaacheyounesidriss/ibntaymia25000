import { describe, expect, it } from "vitest";
import { guardStudentValues } from "./data-guards";
import { DATA_TABLES } from "./data-explorer";

describe("student archive protections", () => {
  it("does not permit deleting students", () => {
    expect(DATA_TABLES.find(t => t.name === "students")?.noDelete).toBe(true);
  });
  it("rejects raw strike-off changes even for administrative editing", () => {
    expect(() => guardStudentValues({ enrollment_status: "struck_off" }, true)).toThrow();
  });
  it("rejects altering the recorded strike-off decision", () => {
    expect(() => guardStudentValues({ struck_off_by: "another-user" }, true)).toThrow();
  });
  it("allows editing parent contact numbers", () => {
    expect(() => guardStudentValues({ father_phone: "0551234567" }, true)).not.toThrow();
  });
});