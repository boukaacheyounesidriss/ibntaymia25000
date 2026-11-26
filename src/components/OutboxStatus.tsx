import { useEffect, useState } from "react";
import { CloudUpload, AlertTriangle, X } from "lucide-react";
import { flushAttendanceOutbox, onOutboxChange, readOutbox, removeQueued, type QueuedAttendance } from "@/lib/attendance-outbox";

/** Floating notice of attendance saved on this device and not yet delivered. */
export function OutboxStatus() {
  const [items, setItems] = useState<QueuedAttendance[]>([]);
  const [open, setOpen] = useState(false);
  useEffect(() => { const r = () => setItems(readOutbox()); r(); return onOutboxChange(r); }, []);
  if (!items.length) return null;
  const failed = items.filter((i) => i.error).length;
  return (
    <div className="fixed inset-x-2 bottom-20 z-50 mx-auto max-w-md rounded-xl border border-border bg-card p-3 text-sm shadow-lg" dir="rtl">
      <button className="flex w-full items-center gap-2 text-start" onClick={() => setOpen((o) => !o)}>
        {failed ? <AlertTriangle className="h-4 w-4 text-destructive" /> : <CloudUpload className="h-4 w-4 text-primary" />}
        <span className="flex-1">{items.length} حصة محفوظة على الجهاز — تُرسل للإدارة تلقائياً عند الاتصال</span>
      </button>
      {open && (
        <ul className="mt-2 space-y-2">
          {items.map((i) => (
            <li key={i.id} className="flex items-start gap-2 rounded-lg bg-muted p-2">
              <div className="flex-1">
                <p className="font-medium">{i.label}</p>
                {i.error && <p className="text-xs text-destructive">{i.error}</p>}
              </div>
              {i.error && <button aria-label="حذف من الجهاز" onClick={() => confirm("حذف هذا التسجيل من الجهاز نهائياً؟") && removeQueued(i.id)}><X className="h-4 w-4" /></button>}
            </li>
          ))}
          <li><button className="text-xs text-primary underline" onClick={() => void flushAttendanceOutbox()}>إرسال الآن</button></li>
        </ul>
      )}
    </div>
  );
}
