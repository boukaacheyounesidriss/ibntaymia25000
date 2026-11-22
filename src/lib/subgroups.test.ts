import { describe, expect, it } from "vitest";
import { defaultScope, studentsForScope, splitInHalves } from "./subgroups";

const list = [
  { id: "a", full_name: "أحمد", subgroup: "g1" },
  { id: "b", full_name: "بلال", subgroup: "g2" },
  { id: "c", full_name: "جمال", subgroup: null },
];

describe("subgroups", () => {
  it("a G1 lab slot shows only G1 students", () => {
    expect(studentsForScope(list, "g1").map((s) => s.id)).toEqual(["a"]);
  });
  it("merging both groups shows the whole class", () => {
    expect(studentsForScope(list, "merged")).toHaveLength(3);
  });
  it("slot label picks the default group", () => {
    expect(defaultScope("g2")).toBe("g2");
    expect(defaultScope("all")).toBe("all");
  });
  it("odd class: first group gets the extra student", () => {
    const m = splitInHalves(list);
    expect([...m.values()].filter((g) => g === "g1")).toHaveLength(2);
  });
});
