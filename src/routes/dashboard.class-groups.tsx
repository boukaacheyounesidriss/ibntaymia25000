import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Shuffle, Users } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { friendlyError } from "@/lib/friendly-error";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export const Route = createFileRoute("/dashboard/class-groups")({
  component: ClassGroupsPage,
  head: () => ({
    meta: [
      { title: "أفواج الأعمال التطبيقية — إداروم" },
      { name: "description", content: "توزيع تلاميذ القسم على الفوج 1 والفوج 2 وتحديد فوج حصص المخبر والأعمال الموجهة." },
      { property: "og:title", content: "أفواج الأعمال التطبيقية — إداروم" },
      { property: "og:description", content: "تقسيم الأقسام إلى أفواج للأعمال التطبيقية والمخبرية من الهاتف." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

const DAYS = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];
const GL: Record<string, string> = { all: "القسم كاملاً", g1: "الفوج 1", g2: "الفوج 2" };

function ClassGroupsPage() {
  const { user, hasRole } = useAuth();
  const qc = useQueryClient();
  const isMgmt = hasRole("admin") || hasRole("director") || hasRole("supervisor");
  const [classId, setClassId] = useState<string>("");

  const { data: classes = [] } = useQuery({
    queryKey: ["cg-classes", user?.id, isMgmt],
    enabled: !!user,
    queryFn: async () => {
      if (isMgmt) {
        const { data } = await supabase.from("classes").select("id, name").order("name");
        return data ?? [];
      }
      const { data } = await supabase.from("class_teachers").select("class_id, classes(id, name)").eq("teacher_id", user!.id);
      const m = new Map<string, { id: string; name: string }>();
      (data ?? []).forEach((r) => { const c = r.classes as unknown as { id: string; name: string } | null; if (c) m.set(c.id, c); });
      return [...m.values()].sort((a, b) => a.name.localeCompare(b.name, "ar"));
    },
  });
  useEffect(() => { if (!classId && classes[0]) setClassId(classes[0].id); }, [classes, classId]);

  const { data: students = [] } = useQuery({
    queryKey: ["cg-students", classId],
    enabled: !!classId,
    queryFn: async () => {
      const { data, error } = await supabase.from("students").select("id, full_name, subgroup")
        .eq("class_id", classId).eq("enrollment_status", "active").order("full_name");
      if (error) throw error;
      return data ?? [];
    },
  });

  const { data: slots = [] } = useQuery({
    queryKey: ["cg-slots", classId, user?.id, isMgmt],
    enabled: !!classId && !!user,
    queryFn: async () => {
      let q = supabase.from("schedule_slots").select("id, subject, weekday, start_time, end_time, group_label, teacher_id")
        .eq("class_id", classId).eq("is_active", true);
      if (!isMgmt) q = q.eq("teacher_id", user!.id);
      const { data } = await q.order("weekday").order("start_time");
      return data ?? [];
    },
  });

  const counts = useMemo(() => ({
    g1: students.filter((s) => s.subgroup === "g1").length,
    g2: students.filter((s) => s.subgroup === "g2").length,
    none: students.filter((s) => !s.subgroup).length,
  }), [students]);

  async function setGroup(id: string, g: "g1" | "g2") {
    qc.setQueryData(["cg-students", classId], (old: typeof students | undefined) => old?.map((s) => s.id === id ? { ...s, subgroup: g } : s));
    const { error } = await supabase.rpc("set_student_subgroup", { _student: id, _group: g });
    if (error) { toast.error(friendlyError(error)); qc.invalidateQueries({ queryKey: ["cg-students", classId] }); }
  }
  async function autoSplit() {
    if (counts.g1 + counts.g2 > 0 && !confirm("سيُعاد توزيع كل تلاميذ القسم أبجدياً. متابعة؟")) return;
    const { error } = await supabase.rpc("auto_split_class_subgroups", { _class: classId });
    if (error) return toast.error(friendlyError(error));
    toast.success("تم التقسيم: النصف الأول أبجدياً فوج 1");
    qc.invalidateQueries({ queryKey: ["cg-students", classId] });
  }
  async function setSlot(id: string, g: string) {
    const { error } = await supabase.rpc("set_slot_group", { _slot: id, _group: g });
    if (error) return toast.error(friendlyError(error));
    toast.success("تم تحديد فوج الحصة");
    qc.invalidateQueries({ queryKey: ["cg-slots"] });
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4 pb-24">
      <h1 className="font-display text-2xl font-bold">أفواج الأعمال التطبيقية</h1>
      <p className="text-sm text-muted-foreground">للأعمال التطبيقية والمخبرية والموجهة: وزّع التلاميذ على فوجين، وحدّد فوج كل حصة. شاشة الحضور تعرض الفوج المعني فقط.</p>

      {!classes.length && <p className="text-sm text-muted-foreground">لا أقسام مسندة إليك.</p>}
      {!!classes.length && (
        <Select value={classId} onValueChange={setClassId}>
          <SelectTrigger className="min-h-12"><SelectValue placeholder="اختر القسم" /></SelectTrigger>
          <SelectContent>{classes.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</SelectContent>
        </Select>
      )}

      {classId && (
        <>
          <Card>
            <CardContent className="flex flex-wrap items-center justify-between gap-2 pt-4">
              <div className="flex flex-wrap gap-1 text-sm">
                <Badge>فوج 1: {counts.g1}</Badge>
                <Badge variant="secondary">فوج 2: {counts.g2}</Badge>
                {counts.none > 0 && <Badge variant="destructive">غير موزع: {counts.none}</Badge>}
              </div>
              <Button onClick={autoSplit} className="min-h-11 gap-2"><Shuffle className="h-4 w-4" />تقسيم آلي</Button>
            </CardContent>
          </Card>

          <section className="space-y-2">
            <h2 className="font-semibold">فوج الحصص {isMgmt ? "" : "(حصصك في هذا القسم)"}</h2>
            {!slots.length && <p className="text-sm text-muted-foreground">لا حصص.</p>}
            {slots.map((s) => (
              <div key={s.id} className="flex items-center justify-between gap-2 rounded-xl border bg-card p-3 text-sm">
                <div className="min-w-0">
                  <p className="truncate font-medium">{s.subject}</p>
                  <p className="text-xs text-muted-foreground">{DAYS[s.weekday]} <span className="ltr">{s.start_time.slice(0, 5)}–{s.end_time.slice(0, 5)}</span></p>
                </div>
                <Select value={s.group_label} onValueChange={(v) => setSlot(s.id, v)}>
                  <SelectTrigger className="min-h-11 w-36"><SelectValue /></SelectTrigger>
                  <SelectContent>{Object.entries(GL).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            ))}
          </section>

          <section className="space-y-2">
            <h2 className="flex items-center gap-1 font-semibold"><Users className="h-4 w-4" />التلاميذ ({students.length})</h2>
            {students.map((s, i) => (
              <div key={s.id} className="flex items-center justify-between gap-2 rounded-xl border bg-card p-2 ps-3">
                <span className="truncate text-sm"><span className="text-muted-foreground">{i + 1}.</span> {s.full_name}</span>
                <div className="flex shrink-0 gap-1">
                  {(["g1", "g2"] as const).map((g) => (
                    <button key={g} type="button" onClick={() => setGroup(s.id, g)} aria-pressed={s.subgroup === g}
                      className={`min-h-11 min-w-14 rounded-lg border text-sm font-semibold ${s.subgroup === g ? "border-primary bg-primary text-primary-foreground" : "bg-background"}`}>
                      {g === "g1" ? "ف1" : "ف2"}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </section>
        </>
      )}
    </div>
  );
}
