export const WEEKDAYS = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];
export const POST_KINDS: Record<string, string> = {
  lesson: "درس", summary: "ملخص", homework: "واجب", tip: "نصيحة", opportunity: "فرصة", event: "حدث",
};
export const MEETING_TARGETS: Record<string, string> = {
  teacher: "أستاذ", administration: "الإدارة", counselor: "مستشار التوجيه", club: "النوادي",
};
export const MEETING_STATUS: Record<string, string> = {
  pending: "قيد الانتظار", approved: "مقبول", rejected: "مرفوض", done: "تم",
};
/** Only http(s) links are allowed in posts. */
export function safeLink(url: string | null | undefined): string | null {
  if (!url) return null;
  try { const u = new URL(url.trim()); return u.protocol === "https:" || u.protocol === "http:" ? u.toString() : null; } catch { return null; }
}
