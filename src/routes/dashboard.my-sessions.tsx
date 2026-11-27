import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { friendlyError } from "@/lib/friendly-error";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

export const Route = createFileRoute("/dashboard/my-sessions")({
  head: () => ({
    meta: [
      { title: "حصصي المسجلة — إداروم" },
      { name: "description", content: "مراجعة الأستاذ لحضور الحصص التي سجلها وتعديلها مرة واحدة." },
      { property: "og:title", content: "حصصي المسجلة — إداروم" },
      { property: "og:description", content: "مراجعة الأستاذ لحضور الحصص التي سجلها وتعديلها مرة واحدة." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: MySessions,
});

type Rec = { student_id: string; status: string; students: { full_name: string } | null };
type Sess = { id: string; session_date: string; period: string | null; subject: string | null; teacher_edit_count: number; created_at: string; classes: { name: string } | null; attendance_records: Rec[] };
const LABEL: Record<string, string> = { present: "حاضر", absent: "غائب", late: "متأخر" };
const NEXT: Record<string, string> = { present: "absent", absent: "late", late: "present" };

function MySessions() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const { data: limits } = useQuery({
    queryKey: ["edit-limits"],
    queryFn: async () => {
      const { data } = await supabase.from("access_settings").select("key,value").in("key", ["attendance_teacher_max_edits", "attendance_edit_window_hours"]);
      const m = Object.fromEntries((data ?? []).map((r) => [r.key, Number(r.value)]));
      return { max: m["attendance_teacher_max_edits"] ?? 1, hours: m["attendance_edit_window_hours"] ?? 24 };
    },
  });
  const { data: sessions = [], isLoading } = useQuery({
    queryKey: ["my-sessions", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data, error } = await supabase.from("attendance_sessions")
        .select("id,session_date,period,subject,teacher_edit_count,created_at,classes(name),attendance_records(student_id,status,students(full_name))")
        .eq("teacher_id", user!.id).order("created_at", { ascending: false }).limit(30);
      if (error) throw error;
      return (data ?? []) as unknown as Sess[];
    },
  });
  const [open, setOpen] = useState<string | null>(null);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);

  async function saveEdit(s: Sess) {
    const changes = s.attendance_records.filter((r) => draft[r.student_id] && draft[r.student_id] !== r.status)
      .map((r) => ({ student_id: r.student_id, status: draft[r.student_id] }));
    if (!changes.length) return toast.message("لا تغييرات");
    if (!confirm(`سيُحتسب هذا تعديلك الوحيد لهذه الحصة (${changes.length} تغيير). متابعة؟`)) return;
    setBusy(true);
    const { error } = await supabase.rpc("teacher_edit_attendance", { _session: s.id, _changes: changes });
    setBusy(false);
    if (error) return toast.error(friendlyError(error));
    toast.success("تم حفظ التعديل");
    setOpen(null); setDraft({});
    void qc.invalidateQueries({ queryKey: ["my-sessions"] });
  }

  return (
    <div className="mx-auto max-w-2xl space-y-3 pb-24">
      <h1 className="font-display text-2xl font-bold">حصصي المسجلة</h1>
      <p className="text-sm text-muted-foreground">
        يمكنك تعديل كل حصة {limits?.max ?? 1} مرة فقط خلال {limits?.hours ?? 24} ساعة من تسجيلها.
      </p>
      {isLoading && <p className="text-sm text-muted-foreground">جارٍ التحميل...</p>}
      {!isLoading && !sessions.length && <p className="text-sm text-muted-foreground">لم تسجل أي حصة بعد.</p>}
      {sessions.map((s) => {
        const absent = s.attendance_records.filter((r) => r.status === "absent").length;
        const late = s.attendance_records.filter((r) => r.status === "late").length;
        const expired = Date.now() - new Date(s.created_at).getTime() > (limits?.hours ?? 24) * 3600_000;
        const used = s.teacher_edit_count >= (limits?.max ?? 1);
        const canEdit = !expired && !used;
        return (
          <Card key={s.id}>
            <CardContent className="space-y-2 p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="font-medium">{s.classes?.name} · {s.subject}</div>
                <div className="text-xs text-muted-foreground">{s.session_date} {s.period ? `· ${s.period}` : ""}</div>
              </div>
              <div className="flex flex-wrap gap-2 text-xs">
                <Badge variant="destructive">{absent} غائب</Badge>
                <Badge variant="secondary">{late} متأخر</Badge>
                {used ? <Badge variant="outline">استُعمل التعديل</Badge> : expired ? <Badge variant="outline">انتهت المهلة</Badge> : <Badge>قابل للتعديل</Badge>}
              </div>
              <Button size="sm" variant="outline" className="w-full" onClick={() => { setOpen(open === s.id ? null : s.id); setDraft({}); }}>
                {open === s.id ? "إخفاء" : canEdit ? "عرض وتعديل" : "عرض"}
              </Button>
              {open === s.id && (
                <div className="space-y-1">
                  {s.attendance_records.map((r) => {
                    const st = draft[r.student_id] ?? r.status;
                    return (
                      <button key={r.student_id} type="button" disabled={!canEdit}
                        onClick={() => setDraft((d) => ({ ...d, [r.student_id]: NEXT[st] ?? "present" }))}
                        className="flex min-h-11 w-full items-center justify-between rounded-md border px-3 text-sm disabled:opacity-80">
                        <span>{r.students?.full_name}</span>
                        <span className={st === "absent" ? "text-destructive" : st === "late" ? "text-primary" : "text-muted-foreground"}>{LABEL[st]}</span>
                      </button>
                    );
                  })}
                  {canEdit && <Button className="w-full" disabled={busy} onClick={() => void saveEdit(s)}>حفظ التعديل (مرة واحدة)</Button>}
                </div>
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
