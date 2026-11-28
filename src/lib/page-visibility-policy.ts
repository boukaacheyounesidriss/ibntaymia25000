export type VisibilityRule = { page: string; target_type: string; target: string; hidden: boolean };
export function pageIsHidden(path: string, rules: VisibilityRule[], userId: string, roles: string[], owner: boolean): boolean {
  const page = path.replace(/\/$/, "");
  // The dashboard is the safe destination when all other pages are hidden.
  if (owner || page === "/dashboard") return false;
  const matches = rules.filter((r) => r.page.replace(/\/$/, "") === page);
  const own = matches.find((r) => r.target_type === "user" && r.target === userId);
  if (own) return own.hidden;
  const roleRules = matches.filter((r) => r.target_type === "role" && roles.includes(r.target));
  if (roleRules.length) return roleRules.some((r) => r.hidden);
  return matches.find((r) => r.target_type === "all")?.hidden ?? false;
}
