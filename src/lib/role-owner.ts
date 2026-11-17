/** Immutable, verified account identity; email and editable metadata never authorize ownership. */
export const ROLE_OWNER_ID = "178bd57a-486c-46a5-b395-4199bde4b4f3";

export function isRoleOwnerIdentity(userId: string | undefined | null): boolean {
  return userId === ROLE_OWNER_ID;
}

export async function requireRoleOwner(db: { rpc: (name: "is_role_owner") => PromiseLike<{ data: unknown; error: { message: string } | null }> }) {
  const { data, error } = await db.rpc("is_role_owner");
  if (error || data !== true) throw new Error("إدارة الأدوار والصلاحيات محجوزة لصاحب المؤسسة فقط.");
}

export function guardOwnerAccount(callerId: string, targetId: string) {
  if (isRoleOwnerIdentity(targetId) && !isRoleOwnerIdentity(callerId)) {
    throw new Error("لا يمكن لأي حساب آخر تغيير حساب صاحب المؤسسة.");
  }
}