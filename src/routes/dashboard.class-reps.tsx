import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { UserCog, KeyRound } from "lucide-react";

import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export const Route = createFileRoute("/dashboard/class-reps")({
  component: ClassRepsPage,
  head: () => ({
    meta: [
      { title: "إدارة مسؤولي الأقسام — إداروم" },
      { name: "description", content: "تعيين أو استبدال مسؤول القسم ونائبه لكل قسم، وإعادة تعيين رموز إمضاء الأساتذة." },
      { property: "og:title", content: "إدارة مسؤولي الأقسام — إداروم" },
      { property: "og:description", content: "تعيين مسؤولي الأقسام ونوابهم ومنح الصلاحيات تلقائياً." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

type Kind = "rep" | "deputy";
const clean = (m: string) => m.replace(/^[A-Z_]+:\s*/, "");

function ClassRepsPage() {
  const qc = useQueryClient();
  const [classId, setClassId] = useState("");

  const { data: classes = [] } = useQuery({
    queryKey: ["classes-list"],
    queryFn: async () => {
      const { data, error } = await supabase.from("classes").select("id, name").order("name");
      if (error) throw error;
      return data ?? [];
    },
  });
  const { data: reps = [] } = useQuery({
    queryKey: ["class-reps"],
    queryFn: async () => {
      const { data, error } = await supabase.from("class_representatives").select("id, class_id, student_id, kind, students(full_name)");
      if (error) throw error;
      return (data ?? []) as unknown as { id: string; class_id: string; student_id: string; kind: Kind; students: { full_name: string } | null }[];
    },
  });
  const { data: students = [] } = useQuery({
    queryKey: ["class-students", classId],
    enabled: !!classId,
    queryFn: async () => {
      const { data, error } = await supabase.from("students").select("id, full_name, user_id")
        .eq("class_id", classId).eq("enrollment_status", "active").order("full_name");
      if (error) throw error;
      return data ?? [];
    },
  });
  const { data: teachers = [] } = useQuery({
    queryKey: ["teachers-list"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("list_teachers");
      if (error) throw error;
      return data ?? [];
    },
  });

  async function assign(kind: Kind, studentId: string) {
    const existing = reps.find((r) => r.class_id === classId && r.kind === kind);
    const res = existing
      ? await supabase.from("class_representatives").update({ student_id: studentId }).eq("id", existing.id)
      : await supabase.from("class_representatives").insert({ class_id: classId, student_id: studentId, kind, user_id: "00000000-0000-0000-0000-000000000000" });
    if (res.error) return toast.error(clean(res.error.message));
    toast.success(kind === "rep" ? "تم تعيين مسؤول القسم" : "تم تعيين نائب مسؤول القسم");
    qc.invalidateQueries({ queryKey: ["class-reps"] });
  }
  async function remove(id: string) {
    const { error } = await supabase.from("class_representatives").delete().eq("id", id);
    if (error) return toast.error(clean(error.message));
    toast.success("تم سحب الصفة والصلاحية");
    qc.invalidateQueries({ queryKey: ["class-reps"] });
  }
  async function resetPin(id: string, name: string) {
    if (!confirm(`إعادة تعيين رمز الإمضاء للأستاذ ${name}؟`)) return;
    const { error } = await supabase.rpc("reset_teacher_attendance_pin", { _teacher: id });
    if (error) return toast.error(clean(error.message));
    toast.success("تم حذف الرمز؛ على الأستاذ إنشاء رمز جديد من ملفه الشخصي");
  }

  return (
    <div className="mx-auto max-w-5xl space-y-4 p-4">
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2 font-display"><UserCog className="h-5 w-5" /> مسؤولو الأقسام</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <Select value={classId} onValueChange={setClassId}>
            <SelectTrigger className="max-w-sm"><SelectValue placeholder="اختر القسم" /></SelectTrigger>
            <SelectContent>{classes.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</SelectContent>
          </Select>
          {classId && (
            <div className="grid gap-4 sm:grid-cols-2">
              {(["rep", "deputy"] as Kind[]).map((kind) => {
                const cur = reps.find((r) => r.class_id === classId && r.kind === kind);
                return (
                  <div key={kind} className="space-y-2 rounded-md border p-3">
                    <p className="font-medium">{kind === "rep" ? "مسؤول القسم" : "نائب مسؤول القسم"}</p>
                    <p className="text-sm text-muted-foreground">الحالي: {cur?.students?.full_name ?? "غير معيّن"}</p>
                    <Select value="" onValueChange={(v) => assign(kind, v)}>
                      <SelectTrigger><SelectValue placeholder={cur ? "استبدال بـ..." : "تعيين..."} /></SelectTrigger>
                      <SelectContent>
                        {students.map((s) => (
                          <SelectItem key={s.id} value={s.id} disabled={!s.user_id}>
                            {s.full_name}{!s.user_id ? " (بلا حساب)" : ""}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {cur && <Button variant="outline" size="sm" onClick={() => remove(cur.id)}>سحب الصفة</Button>}
                  </div>
                );
              })}
            </div>
          )}
          <p className="text-xs text-muted-foreground">يجب أن يملك التلميذ حساباً في النظام ليُعيَّن. تُمنح الصلاحية وتُسحب تلقائياً.</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2 font-display"><KeyRound className="h-5 w-5" /> إعادة تعيين رمز إمضاء الأستاذ</CardTitle></CardHeader>
        <CardContent>
          {!teachers.length ? <p className="text-sm text-muted-foreground">لا يوجد أساتذة مسجلون بعد.</p> : (
            <ul className="divide-y divide-border">
              {teachers.map((t) => (
                <li key={t.id} className="flex items-center justify-between py-2 text-sm">
                  <span>{t.full_name}</span>
                  <Button variant="outline" size="sm" onClick={() => resetPin(t.id, t.full_name)}>إعادة تعيين</Button>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
