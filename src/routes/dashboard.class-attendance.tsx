import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { CheckCircle2, Clock, Save, Users } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { friendlyError } from "@/lib/friendly-error";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Link } from "@tanstack/react-router";
import { ScopeTabs } from "@/components/ScopeTabs";
import { defaultScope, SCOPE_LABEL, studentsForScope, type Scope } from "@/lib/subgroups";

export const Route = createFileRoute("/dashboard/class-attendance")({
  component: TeacherQuickAttendance,
  head: () => ({
    meta: [
      { title: "حضور حصتي — إداروم" },
      { name: "description", content: "تسجيل حضور الحصة الحالية للأستاذ من الهاتف بلمسة واحدة لكل تلميذ." },
      { property: "og:title", content: "حضور حصتي — إداروم" },
      { property: "og:description", content: "شاشة الأستاذ السريعة لتحديد الغائبين والمتأخرين." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

type Mark = "present" | "absent" | "late";
type Slot = { id: string; class_id: string; subject: string; start_time: string; end_time: string; period_no: number | null; room: string | null; group_label: string; classes: { name: string } | null };

function localDate() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
const periodOf = (s: Slot) => (s.period_no != null ? String(s.period_no) : s.start_time.slice(0, 5));

function TeacherQuickAttendance() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const today = localDate();
  const weekday = new Date().getDay();
  const nowHM = new Date().toTimeString().slice(0, 5);
  const [slotId, setSlotId] = useState<string | null>(null);
  const [marks, setMarks] = useState<Record<string, Mark>>({});
  const [busy, setBusy] = useState(false);

  const { data: slots = [], isLoading } = useQuery({
    queryKey: ["qa-slots", user?.id, weekday],
    enabled: !!user,
    queryFn: async (): Promise<Slot[]> => {
      const { data, error } = await supabase.from("schedule_slots")
        .select("id, class_id, subject, start_time, end_time, period_no, room, group_label, classes(name)")
        .eq("teacher_id", user!.id).eq("weekday", weekday).eq("is_active", true).order("start_time");
      if (error) throw error;
      return (data ?? []) as unknown as Slot[];
    },
  });

  const { data: done = [] } = useQuery({
    queryKey: ["qa-done", user?.id, today],
    enabled: !!user,
    queryFn: async () => {
      const { data } = await supabase.from("attendance_sessions").select("id, slot_id, class_id, period, group_scope").eq("session_date", today);
      return data ?? [];
    },
  });

  useEffect(() => {
    if (slotId || !slots.length) return;
    const cur = slots.find((s) => s.start_time.slice(0, 5) <= nowHM && nowHM < s.end_time.slice(0, 5))
      ?? slots.find((s) => s.start_time.slice(0, 5) > nowHM) ?? slots[slots.length - 1];
    setSlotId(cur.id);
  }, [slots, slotId, nowHM]);

  const slot = slots.find((s) => s.id === slotId) ?? null;
  const [scope, setScope] = useState<Scope>("all");
  const isDone = (s: Slot, sc: Scope = defaultScope(s.group_label)) => done.some((d) => d.class_id === s.class_id && d.period === periodOf(s)
    && (sc === "all" || sc === "merged" || d.group_scope === "all" || d.group_scope === "merged" || d.group_scope === sc));

  const { data: allStudents = [] } = useQuery({
    queryKey: ["qa-students", slot?.class_id],
    enabled: !!slot,
    queryFn: async () => {
      const { data, error } = await supabase.from("students").select("id, full_name, subgroup")
        .eq("class_id", slot!.class_id).eq("enrollment_status", "active").order("full_name");
      if (error) throw error;
      return data ?? [];
    },
  });

  const { data: blocked = [] } = useQuery({
    queryKey: ["qa-blocked", slot?.class_id],
    enabled: !!slot,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("class_blocked_students", { _class: slot!.class_id });
      if (error) throw error;
      return data ?? [];
    },
  });
  const blockedMap = useMemo(() => new Map(blocked.map((b) => [b.student_id, b])), [blocked]);

  useEffect(() => { setMarks({}); if (slot) setScope(defaultScope(slot.group_label)); }, [slotId]); // eslint-disable-line react-hooks/exhaustive-deps
  const scoped = useMemo(() => studentsForScope(allStudents, scope), [allStudents, scope]);
  const students = useMemo(() => scoped.filter((s) => !blockedMap.has(s.id)), [scoped, blockedMap]);
  const lockedList = useMemo(() => scoped.filter((s) => blockedMap.has(s.id)), [scoped, blockedMap]);
  const unassigned = allStudents.filter((s) => !s.subgroup).length;
  const counts = useMemo(() => {
    const v = Object.values(marks);
    return { absent: v.filter((x) => x === "absent").length, late: v.filter((x) => x === "late").length };
  }, [marks]);

  const cycle = (id: string) => setMarks((m) => {
    const c = m[id] ?? "present";
    return { ...m, [id]: c === "present" ? "absent" : c === "absent" ? "late" : "present" };
  });

  async function save() {
    if (!slot || !user) return;
    if (!students.length) return toast.error("لا تلاميذ في هذا الفوج. وزّع الأفواج أولاً");
    if (!confirm(`${SCOPE_LABEL[scope]} — تأكيد: ${students.length - counts.absent - counts.late} حاضر، ${counts.absent} غائب، ${counts.late} متأخر؟`)) return;
    setBusy(true);
    const { data: sess, error } = await supabase.from("attendance_sessions").insert({
      class_id: slot.class_id, teacher_id: user.id, session_date: today, period: periodOf(slot),
      subject: slot.subject, slot_id: slot.id, session_type: "regular", group_scope: scope,
      note: scope === "merged" ? "حصة مجمّعة استثنائياً للفوجين" : null,
    } as never).select("id").single();
    if (error) { setBusy(false); return toast.error(error.code === "23505" ? "حضور هذه الحصة مسجل مسبقاً" : friendlyError(error)); }
    const rows = students.map((s) => ({ session_id: sess.id, student_id: s.id, status: marks[s.id] ?? "present" }));
    const { error: e2 } = await supabase.from("attendance_records").upsert(rows, { onConflict: "session_id,student_id" });
    setBusy(false);
    if (e2) return toast.error(friendlyError(e2));
    toast.success("تم حفظ حضور الحصة");
    setMarks({});
    qc.invalidateQueries({ queryKey: ["qa-done"] });
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4 pb-28">
      <h1 className="font-display text-2xl font-bold">حضور حصتي</h1>
      {isLoading && <p className="text-sm text-muted-foreground">جارٍ التحميل...</p>}
      {!isLoading && !slots.length && <p className="text-sm text-muted-foreground">لا حصص لك في جدول اليوم.</p>}

      <div className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
        {slots.map((s) => {
          const cur = s.start_time.slice(0, 5) <= nowHM && nowHM < s.end_time.slice(0, 5);
          return (
            <button key={s.id} onClick={() => setSlotId(s.id)}
              className={`min-w-36 shrink-0 rounded-xl border p-3 text-start text-sm ${s.id === slotId ? "border-primary bg-primary/10" : "bg-card"}`}>
              <p className="ltr font-semibold">{s.start_time.slice(0, 5)}–{s.end_time.slice(0, 5)}</p>
              <p className="truncate">{s.classes?.name}</p>
              <div className="mt-1 flex gap-1">
                {cur && <Badge><Clock className="me-1 h-3 w-3" />الآن</Badge>}
                {isDone(s) && <Badge variant="secondary"><CheckCircle2 className="me-1 h-3 w-3" />مسجَّل</Badge>}
              </div>
            </button>
          );
        })}
      </div>

      {slot && (
        <>
          <Card>
            <CardContent className="flex flex-wrap items-center justify-between gap-2 pt-4 text-sm">
              <div>
                <p className="font-semibold">{slot.classes?.name} · {slot.subject}</p>
                <p className="text-muted-foreground">{slot.room ? `القاعة ${slot.room} · ` : ""}<Users className="inline h-3 w-3" /> {students.length} تلميذ</p>
              </div>
              <div className="flex gap-1">
                <Badge variant="destructive">{counts.absent} غائب</Badge>
                <Badge variant="outline">{counts.late} متأخر</Badge>
              </div>
            </CardContent>
          </Card>

          <ScopeTabs value={scope} onChange={(v) => { setScope(v); setMarks({}); }} slotGroup={slot.group_label} />
          {scope === "merged" && <p className="rounded-lg bg-accent/20 p-2 text-xs">حصة استثنائية: يُسجَّل حضور القسم كاملاً (غياب أستاذ الفوج الآخر مثلاً) وتُدوَّن ملاحظة للإدارة.</p>}
          {(scope === "g1" || scope === "g2") && unassigned > 0 && (
            <p className="rounded-lg border border-destructive/40 p-2 text-xs">{unassigned} تلميذ غير موزَّع على الأفواج. <Link to="/dashboard/class-groups" className="font-semibold underline">وزّع الأفواج</Link></p>
          )}
          {isDone(slot, scope) ? (
            <Card><CardContent className="flex items-center gap-2 pt-4 text-sm"><CheckCircle2 className="h-5 w-5 text-primary" />حضور هذه الحصة مسجّل. للتصحيح استعمل صفحة تسجيل الحضور الكاملة.</CardContent></Card>
          ) : (
            <>
              {lockedList.length > 0 && (
                <div className="rounded-xl border border-destructive/50 bg-destructive/5 p-3 text-sm">
                  <p className="mb-2 font-semibold text-destructive">غياب غير مبرَّر — لا يُسجَّل حتى تبرّره الإدارة ({lockedList.length})</p>
                  <ul className="space-y-1">
                    {lockedList.map((s) => {
                      const b = blockedMap.get(s.id);
                      return (
                        <li key={s.id} className="flex items-center justify-between gap-2 rounded-lg bg-card px-3 py-2">
                          <span>{s.full_name}</span>
                          <Badge variant="destructive">منذ {b?.since_date} · {b?.absences} حصة</Badge>
                        </li>
                      );
                    })}
                  </ul>
                  <p className="mt-2 text-xs text-muted-foreground">يُوجَّه التلميذ إلى الإدارة (المراقب) لتبرير غيابه أو أخذ تصريح دخول.</p>
                </div>
              )}
              <p className="text-xs text-muted-foreground">الجميع حاضر افتراضياً. المس التلميذ: غائب ← متأخر ← حاضر.</p>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {students.map((s, i) => {
                  const m = marks[s.id] ?? "present";
                  const tone = m === "absent" ? "border-destructive bg-destructive/10" : m === "late" ? "border-accent bg-accent/20" : "bg-card";
                  return (
                    <button key={s.id} onClick={() => cycle(s.id)} className={`flex min-h-14 items-center justify-between rounded-xl border px-3 text-start ${tone}`}>
                      <span className="text-sm"><span className="text-muted-foreground">{i + 1}.</span> {s.full_name}</span>
                      <span className="text-xs font-semibold">{m === "absent" ? "غائب" : m === "late" ? "متأخر" : "حاضر"}</span>
                    </button>
                  );
                })}
              </div>
              <div className="fixed inset-x-0 bottom-16 z-30 px-4 md:bottom-4">
                <Button size="lg" className="mx-auto flex min-h-12 w-full max-w-2xl gap-2" disabled={busy || !students.length} onClick={save}>
                  <Save className="h-5 w-5" /> حفظ الحضور
                </Button>
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}
