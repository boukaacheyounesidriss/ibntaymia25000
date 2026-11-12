/** Normalise an Algerian phone number. Returns "" for empty, null for invalid. */
export function normalizeDzPhone(raw: string): string | null {
  let d = raw.replace(/[^\d+]/g, "");
  if (d === "") return "";
  if (d.startsWith("+213")) d = "0" + d.slice(4);
  else if (d.startsWith("00213")) d = "0" + d.slice(5);
  else if (d.startsWith("213") && d.length === 12) d = "0" + d.slice(3);
  if (/^0[567]\d{8}$/.test(d)) return d; // mobile
  if (/^0[1-9]\d{7}$/.test(d)) return d; // landline
  return null;
}
