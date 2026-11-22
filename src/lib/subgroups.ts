/** Lab/TD subgroup helpers: a slot may be for the whole class or one of two subgroups. */
export type Subgroup = "g1" | "g2";
export type Scope = "all" | Subgroup | "merged";

export const SCOPE_LABEL: Record<Scope, string> = {
  all: "القسم كاملاً",
  g1: "الفوج 1",
  g2: "الفوج 2",
  merged: "دمج الفوجين",
};

/** Default scope for a slot from its schedule group label. */
export function defaultScope(groupLabel: string | null | undefined): Scope {
  return groupLabel === "g1" || groupLabel === "g2" ? groupLabel : "all";
}

/** Students that belong in a session of the given scope. */
export function studentsForScope<T extends { subgroup?: string | null }>(list: T[], scope: Scope): T[] {
  if (scope === "all" || scope === "merged") return list;
  return list.filter((s) => s.subgroup === scope);
}

/** Alphabetical split in halves (first half = G1), same rule as the server. */
export function splitInHalves<T extends { full_name: string }>(list: T[]): Map<T, Subgroup> {
  const sorted = [...list].sort((a, b) => a.full_name.localeCompare(b.full_name, "ar"));
  const half = Math.ceil(sorted.length / 2);
  return new Map(sorted.map((s, i) => [s, i < half ? "g1" : "g2"]));
}
