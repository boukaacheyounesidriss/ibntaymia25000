import { FileCheck, MessageSquare, Phone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { normalizeDzPhone } from "@/lib/phone";
import { smsComposerLink } from "@/lib/telegram-alerts";

type Student = { full_name: string; guardian_name: string | null; guardian_phone: string | null; father_phone: string | null; mother_phone: string | null };
export function AbsenceStudentRow({ student, status, justified, period, day, onJustify }: {
  student: Student | null; status: string; justified: boolean; period: string | null | undefined; day: string; onJustify?: () => void;
}) {
  const contacts = [{ label: "الأب", phone: student?.father_phone }, { label: "الأم", phone: student?.mother_phone }].flatMap((c) => {
    const phone = c.phone ? normalizeDzPhone(c.phone) : null;
    return phone ? [{ ...c, phone }] : [];
  });
  if (!contacts.length) {
    const phone = student?.guardian_phone ? normalizeDzPhone(student.guardian_phone) : null;
    if (phone) contacts.push({ label: "الولي", phone });
  }
  const label = status === "absent" ? "غائب" : status === "late" ? "متأخر" : "بعذر";
  return <article aria-label={`غياب ${student?.full_name ?? "تلميذ"}`} className="min-w-0 space-y-3 px-3 py-4 text-sm">
    <div className="grid grid-cols-[minmax(0,1fr)_auto] items-start gap-2">
      <p className="min-w-0 break-words font-semibold">{student?.full_name ?? "—"}</p>
      <span className="shrink-0 text-xs text-muted-foreground">حصة {period ?? "—"}</span>
    </div>
    <div className="flex flex-wrap gap-2"><Badge variant={status === "absent" ? "destructive" : "secondary"}>{label}</Badge><Badge variant="outline">{justified || status === "excused" ? "مبرَّر" : "غير مبرَّر"}</Badge></div>
    {onJustify && !justified && status !== "excused" && <Button variant="secondary" className="h-11 w-full sm:w-auto" onClick={onJustify}><FileCheck /> إضافة تبرير</Button>}
    <div className="grid gap-2 sm:grid-cols-2">
      {contacts.map((c) => {
        const body = `السيد/السيدة ${student?.guardian_name || "ولي التلميذ"}، نعلمكم بتسجيل ${label} للتلميذ(ة) ${student?.full_name ?? ""} بتاريخ ${day}، الحصة ${period ?? "—"}. يرجى التواصل مع إدارة الثانوية.`;
        const sms = smsComposerLink(c.phone, body, typeof navigator !== "undefined" && /iPad|iPhone|iPod/.test(navigator.userAgent));
        return <div key={c.label} className="grid grid-cols-2 gap-2">
          <Button asChild variant="outline" className="h-11 min-w-0 px-2"><a href={`tel:${c.phone}`} aria-label={`اتصال ب${c.label}`}><Phone /> اتصال {c.label}</a></Button>
          <Button asChild className="h-11 min-w-0 px-2"><a href={sms} aria-label={`رسالة إلى ${c.label}`}><MessageSquare /> SMS {c.label}</a></Button>
        </div>;
      })}
    </div>
    {!contacts.length && <p className="text-xs text-muted-foreground">لا يوجد رقم ولي صالح</p>}
  </article>;
}
