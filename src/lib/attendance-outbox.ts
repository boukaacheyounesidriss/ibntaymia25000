import { supabase } from "@/integrations/supabase/client";

export type QueuedAttendance = {
  id: string;
  queued_at: string;
  user_id: string;
  session: {
    class_id: string; teacher_id: string; session_date: string; period: string | null;
    subject: string | null; slot_id: string | null; session_type: string; group_scope: string; note: string | null;
  };
  marks: { student_id: string; status: string }[];
  label: string;
  error?: string;
};

const KEY = "idaroom-attendance-outbox";
const EVT = "idaroom-outbox";

export function readOutbox(): QueuedAttendance[] {
  if (typeof window === "undefined") return [];
  try { return JSON.parse(localStorage.getItem(KEY) ?? "[]") as QueuedAttendance[]; } catch { return []; }
}
function write(items: QueuedAttendance[]) {
  localStorage.setItem(KEY, JSON.stringify(items));
  window.dispatchEvent(new Event(EVT));
}
export function onOutboxChange(cb: () => void): () => void {
  window.addEventListener(EVT, cb);
  window.addEventListener("storage", cb);
  return () => { window.removeEventListener(EVT, cb); window.removeEventListener("storage", cb); };
}
export function queueAttendance(item: Omit<QueuedAttendance, "id" | "queued_at">) {
  write([...readOutbox(), { ...item, id: crypto.randomUUID(), queued_at: new Date().toISOString() }]);
}
export function removeQueued(id: string) { write(readOutbox().filter((i) => i.id !== id)); }

/** True when an error means "no network" rather than a rule refusing the data. */
export function isNetworkError(e: unknown): boolean {
  if (typeof navigator !== "undefined" && !navigator.onLine) return true;
  const m = String((e as { message?: string })?.message ?? e);
  return /Failed to fetch|NetworkError|Load failed|network|fetch/i.test(m) && !(e as { code?: string })?.code;
}

/** Sends one queued item. Reuses an existing session of the same slot (saved earlier from this device). */
async function sendOne(item: QueuedAttendance): Promise<void> {
  const s = item.session;
  let sessionId: string | null = null;
  const { data: created, error } = await supabase.from("attendance_sessions").insert(s as never).select("id").single();
  if (error) {
    if (error.code !== "23505" && !/overlap|تداخل|مسجل/.test(error.message)) throw error;
    const { data: existing, error: e2 } = await supabase.from("attendance_sessions").select("id")
      .eq("class_id", s.class_id).eq("session_date", s.session_date).eq("teacher_id", s.teacher_id)
      .eq("group_scope", s.group_scope).match(s.period ? { period: s.period } : {}).maybeSingle();
    if (e2 || !existing) throw new Error("حضور هذه الحصة سُجّل من جهاز آخر");
    sessionId = existing.id;
    const { count } = await supabase.from("attendance_records").select("id", { count: "exact", head: true }).eq("session_id", sessionId);
    if ((count ?? 0) > 0) return; // already delivered earlier
  } else sessionId = created.id;
  const rows = item.marks.map((m) => ({ session_id: sessionId!, student_id: m.student_id, status: m.status }));
  const { error: e3 } = await supabase.from("attendance_records").insert(rows);
  if (e3) throw e3;
}

let running = false;
/** Returns how many queued records reached the administration. */
export async function flushAttendanceOutbox(): Promise<number> {
  if (running || typeof navigator === "undefined" || !navigator.onLine) return 0;
  const items = readOutbox();
  if (!items.length) return 0;
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return 0;
  running = true;
  let sent = 0;
  try {
    for (const item of items) {
      if (item.user_id !== session.user.id) continue;
      try {
        await sendOne(item);
        removeQueued(item.id); sent++;
      } catch (e) {
        if (isNetworkError(e)) break;
        write(readOutbox().map((i) => i.id === item.id ? { ...i, error: String((e as { message?: string })?.message ?? e) } : i));
      }
    }
  } finally { running = false; }
  return sent;
}
