import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { Clock, Delete, Lock, CheckCircle2, RefreshCw } from "lucide-react";

import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

export const Route = createFileRoute("/dashboard/class-rep-attendance")({
  component: KioskPage,
  head: () => ({
    meta: [
      { title: "تسجيل حضور القسم — إداروم" },
      { name: "description", content: "شاشة مسؤول القسم لتحديد الغائبين والمتأخرين وإمضاء الأستاذ برمز PIN." },
      { property: "og:title", content: "تسجيل حضور القسم — إداروم" },
      { property: "og:description", content: "إمضاء حضور الحصة من قاعة الدرس برمز الأستاذ السري." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

type Ctx = {
  class_id: string;
  class_name: string;
  kind: "rep" | "deputy";
  today: string;
  slot: null | { id: string; subject: string | null; start: string; end: string; teacher_name: string; already_done: boolean };
  students: { id: string; name: string }[];
};
type Mark = "present" | "absent" | "late";
const clean = (m: string) => m.replace(/^[A-Z_]+:\s*/, "");

function KioskPage() {
  const qc = useQueryClient();
  const [marks, setMarks] = useState<Record<string, Mark>>({});
  const [pinOpen, setPinOpen] = useState(false);
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [locked, setLocked] = useState(false);

  const { data: ctx, error, isLoading, refetch } = useQuery({
    queryKey: ["kiosk-context"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("kiosk_context");
      if (error) throw error;
      return data as unknown as Ctx;
    },
    refetchInterval: 60_000,
  });

  const cycle = (id: string) =>
    setMarks((m) => {
      const cur = m[id] ?? "present";
      const next: Mark = cur === "present" ? "absent" : cur === "absent" ? "late" : "present";
      return { ...m, [id]: next };
    });

  async function submit() {
    if (!ctx?.slot) return;
    setBusy(true);
    const absent = Object.entries(marks).filter(([, v]) => v === "absent").map(([k]) => k);
    const late = Object.entries(marks).filter(([, v]) => v === "late").map(([k]) => k);
    const { data, error } = await supabase.rpc("kiosk_submit_attendance", { _slot_id: ctx.slot.id, _absent: absent, _late: late, _pin: pin });
    setBusy(false);
    setPin("");
    if (error) return toast.error(clean(error.message));
    const r = data as { ok: boolean; error?: string; minutes?: number; remaining?: number };
    if (!r?.ok) {
      if (r?.error === "PIN_LOCKED") return toast.error(`الرمز مقفل، أعد المحاولة بعد ${r.minutes ?? 15} دقيقة`);
      return toast.error("رمز خاطئ" + (r?.remaining != null ? ` — المتبقي ${r.remaining} محاولة` : ""));
    }
    setPinOpen(false);
    setMarks({});
    setLocked(true);
    toast.success("تم إمضاء الحضور باسم الأستاذ");
    qc.invalidateQueries({ queryKey: ["kiosk-context"] });
  }

  if (isLoading) return <p className="p-6 text-center text-muted-foreground">جارٍ التحميل...</p>;
  if (error) return <p className="p-6 text-center text-destructive">{clean((error as Error).message)}</p>;
  if (!ctx) return null;

  if (locked || ctx.slot?.already_done) {
    return (
      <div className="mx-auto flex min-h-[60vh] max-w-md flex-col items-center justify-center gap-4 p-6 text-center">
        <CheckCircle2 className="h-16 w-16 text-primary" />
        <h1 className="font-display text-2xl">تم تسجيل حضور هذه الحصة</h1>
        <p className="text-muted-foreground">الشاشة مقفلة. تفتح تلقائياً في الحصة التالية.</p>
        <Button variant="outline" onClick={() => { setLocked(false); refetch(); }}>
          <RefreshCw className="me-2 h-4 w-4" /> تحقق من الحصة التالية
        </Button>
      </div>
    );
  }

  const counts = { absent: 0, late: 0 };
  Object.values(marks).forEach((v) => { if (v !== "present") counts[v]++; });

  return (
    <div className="mx-auto max-w-4xl space-y-4 p-4">
      <Card>
        <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2">
          <CardTitle className="font-display">{ctx.class_name}</CardTitle>
          <Badge variant="secondary">{ctx.kind === "rep" ? "مسؤول القسم" : "نائب مسؤول القسم"}</Badge>
        </CardHeader>
        <CardContent>
          {ctx.slot ? (
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <Clock className="h-4 w-4" />
              <span dir="ltr">{ctx.slot.start} - {ctx.slot.end}</span>
              <span className="font-medium">{ctx.slot.subject ?? "حصة"}</span>
              <span className="text-muted-foreground">الأستاذ: {ctx.slot.teacher_name}</span>
            </div>
          ) : (
            <p className="text-muted-foreground">لا توجد حصة مفتوحة للإمضاء الآن (يفتح الإمضاء 10 دقائق قبل الحصة وحتى 20 دقيقة بعد نهايتها).</p>
          )}
        </CardContent>
      </Card>

      {ctx.slot && (
        <>
          <p className="text-sm text-muted-foreground">اضغط على اسم التلميذ: مرة = غائب، مرتين = متأخر، ثلاثاً = حاضر.</p>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {ctx.students.map((s, i) => {
              const m = marks[s.id] ?? "present";
              return (
                <button key={s.id} type="button" onClick={() => cycle(s.id)}
                  className={`flex items-center justify-between rounded-md border p-3 text-start transition-colors ${m === "absent" ? "border-destructive bg-destructive/10" : m === "late" ? "border-accent bg-accent/30" : "border-border bg-card"}`}>
                  <span><span className="me-2 text-xs text-muted-foreground">{i + 1}</span>{s.name}</span>
                  {m !== "present" && <Badge variant={m === "absent" ? "destructive" : "secondary"}>{m === "absent" ? "غائب" : "متأخر"}</Badge>}
                </button>
              );
            })}
          </div>
          <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 rounded-md border bg-background p-3">
            <span className="text-sm">الغائبون: {counts.absent} — المتأخرون: {counts.late} — الحاضرون: {ctx.students.length - counts.absent - counts.late}</span>
            <Button onClick={() => setPinOpen(true)}><Lock className="me-2 h-4 w-4" /> إمضاء الأستاذ</Button>
          </div>
        </>
      )}

      {pinOpen && ctx.slot && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-background/90 p-4" role="dialog" aria-label="إدخال رمز الأستاذ">
          <Card className="w-full max-w-xs">
            <CardHeader><CardTitle className="text-center font-display">رمز الأستاذ {ctx.slot.teacher_name}</CardTitle></CardHeader>
            <CardContent className="space-y-4">
              <div className="flex justify-center gap-2" dir="ltr">
                {Array.from({ length: 6 }).map((_, i) => (
                  <span key={i} className={`h-3 w-3 rounded-full ${i < pin.length ? "bg-primary" : "bg-muted"}`} />
                ))}
              </div>
              <div className="grid grid-cols-3 gap-2" dir="ltr">
                {["1","2","3","4","5","6","7","8","9"].map((d) => (
                  <Button key={d} variant="outline" className="h-14 text-xl" onClick={() => pin.length < 6 && setPin(pin + d)}>{d}</Button>
                ))}
                <Button variant="ghost" className="h-14" aria-label="مسح" onClick={() => setPin(pin.slice(0, -1))}><Delete className="h-5 w-5" /></Button>
                <Button variant="outline" className="h-14 text-xl" onClick={() => pin.length < 6 && setPin(pin + "0")}>0</Button>
                <Button className="h-14" disabled={pin.length < 4 || busy} onClick={submit}>{busy ? "..." : "تأكيد"}</Button>
              </div>
              <Button variant="ghost" className="w-full" onClick={() => { setPin(""); setPinOpen(false); }}>إلغاء</Button>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
