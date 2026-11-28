export type EditLimits = { max: number; hours: number };
export function attendanceEditState(createdAt: string, usedEdits: number, limits: EditLimits, now = Date.now()) {
  const exhausted = usedEdits >= limits.max;
  const expired = limits.hours > 0 && now - new Date(createdAt).getTime() > limits.hours * 3_600_000;
  return { exhausted, expired, canEdit: !exhausted && !expired };
}
