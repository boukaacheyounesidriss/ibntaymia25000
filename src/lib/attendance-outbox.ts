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
  const queued = { ...item, id: crypto.randomUUID(), queued_at: new Date().toISOString() };
  write([...readOutbox(), queued]);
  return queued;
}
export function removeQueued(id: string) { write(readOutbox().filter((i) => i.id !== id)); }

/** True when an error means "no network" rather than a rule refusing the data. */
export function isNetworkError(e: unknown): boolean {
  if (typeof navigator !== "undefined" && !navigator.onLine) return true;
  const m = String((e as { message?: string })?.message ?? e);
  return /Failed to fetch|NetworkError|Load failed|network|fetch/i.test(m) && !(e as { code?: string })?.code;
}

/** One atomic request; the durable receipt makes a lost response safe to retry. */
async function sendOne(item: QueuedAttendance): Promise<void> {
  const { error } = await supabase.rpc("submit_teacher_attendance", {
    _id: item.id, _session: item.session, _marks: item.marks,
  });
  if (error) throw error;
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
