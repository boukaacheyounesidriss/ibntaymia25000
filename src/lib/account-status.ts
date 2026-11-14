export function accountIsDisabled(until: string | null | undefined, now = Date.now()) {
  return Boolean(until && Date.parse(until) > now);
}