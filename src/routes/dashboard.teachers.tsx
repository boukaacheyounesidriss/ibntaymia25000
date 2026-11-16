import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { AlertTriangle, KeyRound, Save } from "lucide-react";

import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";

export const Route = createFileRoute("/dashboard/teachers")({
  component: TeachersPage,
  head: () => ({
    meta: [
      { title: "الأساتذة وقوائم الإسناد — إداروم" },
      { name: "description", content: "قائمة الأساتذة برموزهم الرسمية، حساباتهم، وعدد حصصهم المسندة مع تصحيح الأسماء." },
      { property: "og:title", content: "الأساتذة وقوائم الإسناد — إداروم" },
      { property: "og:description", content: "تصحيح أسماء الأساتذة ومتابعة إسناد الحصص." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

type Row = { code: string; full_name: string; subject: string; user_id: string | null; login_email: string | null; needs_review: boolean };

function TeachersPage() {
  const qc = useQueryClient();
  const [q, setQ] = useState("");
  const [edits, setEdits] = useState<Record<string, string>>({});

  const { data, isLoading, error } = useQuery({
    queryKey: ["teacher-directory"],
    queryFn: async () => {
      const [{ data: rows, error: e1 }, { data: slots, error: e2 }] = await Promise.all([
        supabase.from("teacher_directory").select("code, full_name, subject, user_id, login_email, needs_review").order("subject").order("code"),
        supabase.from("schedule_slots").select("teacher_id").eq("is_active", true).limit(2000),
      ]);
      if (e1) throw e1;
      if (e2) throw e2;
      const counts: Record<string, number> = {};
      let unassigned = 0;
      for (const s of slots ?? []) {
        if (s.teacher_id) counts[s.teacher_id] = (counts[s.teacher_id] ?? 0) + 1;
        else unassigned++;
      }
      return { rows: (rows ?? []) as Row[], counts, unassigned };
    },
  });

  async function save(r: Row) {
    const name = (edits[r.code] ?? "").trim();
    if (!name) return;
    const { error } = await supabase.from("teacher_directory").update({ full_name: name, needs_review: false }).eq("code", r.code);
    if (error) return toast.error(error.message);
    toast.success("تم حفظ الاسم");
    setEdits((e) => ({ ...e, [r.code]: "" }));
    qc.invalidateQueries({ queryKey: ["teacher-directory"] });
  }

  async function confirm(r: Row) {
    const { error } = await supabase.from("teacher_directory").update({ needs_review: false }).eq("code", r.code);
    if (error) return toast.error(error.message);
    qc.invalidateQueries({ queryKey: ["teacher-directory"] });
  }

  async function resetPin(r: Row) {
    if (!r.user_id) return;
    const { error } = await supabase.rpc("reset_teacher_attendance_pin", { _teacher: r.user_id });
    if (error) return toast.error(error.message);
    toast.success("أُعيد تعيين رمز الإمضاء؛ على الأستاذ إنشاء رمز جديد من حسابه");
  }

  if (isLoading) return <p className="p-4 text-muted-foreground">جارٍ التحميل…</p>;
  if (error) return <p className="p-4 text-destructive">{(error as Error).message}</p>;
  const rows = (data?.rows ?? []).filter((r) => !q || (r.full_name + r.code + r.subject).includes(q.trim()));
  const review = (data?.rows ?? []).filter((r) => r.needs_review).length;

  return (
    <div className="space-y-4 p-3 md:p-6" dir="rtl">
      <div>
        <h1 className="font-display text-2xl">الأساتذة وقوائم الإسناد</h1>
        <p className="text-sm text-muted-foreground">
          {data?.rows.length} أستاذاً — حصص بلا أستاذ: {data?.unassigned} — أسماء تحتاج تأكيداً: {review}
        </p>
      </div>
      <Input placeholder="ابحث بالاسم أو الرمز أو المادة" value={q} onChange={(e) => setQ(e.target.value)} />
      <div className="grid gap-3 md:grid-cols-2">
        {rows.map((r) => (
          <Card key={r.code} className={r.needs_review ? "border-accent" : ""}>
            <CardContent className="space-y-2 p-4">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-semibold">{r.full_name}</span>
                <Badge variant="secondary">{r.code}</Badge>
                <Badge variant="outline">{r.user_id ? data?.counts[r.user_id] ?? 0 : 0} حصة</Badge>
                {r.needs_review && (
                  <Badge variant="destructive" className="gap-1"><AlertTriangle className="h-3 w-3" />تأكد من الاسم</Badge>
                )}
              </div>
              <p className="text-xs text-muted-foreground">{r.subject} — {r.login_email}</p>
              <div className="flex gap-2">
                <Input placeholder="تصحيح الاسم" value={edits[r.code] ?? ""} onChange={(e) => setEdits((x) => ({ ...x, [r.code]: e.target.value }))} />
                <Button size="icon" onClick={() => save(r)} aria-label="حفظ"><Save className="h-4 w-4" /></Button>
              </div>
              <div className="flex flex-wrap gap-2">
                {r.needs_review && <Button size="sm" variant="outline" onClick={() => confirm(r)}>الاسم صحيح</Button>}
                <Button size="sm" variant="ghost" onClick={() => resetPin(r)}><KeyRound className="ml-1 h-4 w-4" />إعادة تعيين رمز PIN</Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
