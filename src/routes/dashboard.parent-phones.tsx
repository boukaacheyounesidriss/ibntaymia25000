import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { ChevronRight, ChevronLeft, Check, Phone, Search } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { normalizeDzPhone } from "@/lib/phone";

export const Route = createFileRoute("/dashboard/parent-phones")({
  component: ParentPhonesPage,
  head: () => ({
    meta: [
      { title: "أرقام الأولياء — إداروم" },
      { name: "description", content: "إدخال وتعديل أرقام هواتف أولياء التلاميذ بسرعة من الهاتف." },
      { property: "og:title", content: "أرقام الأولياء — إداروم" },
      { property: "og:description", content: "إدخال سريع لأرقام آباء وأمهات التلاميذ قسماً قسماً." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

type Stu = { id: string; full_name: string; father_phone: string | null; mother_phone: string | null };

function ParentPhonesPage() {
  const qc = useQueryClient();
  const [classId, setClassId] = useState("");
  const [idx, setIdx] = useState(0);
  const [q, setQ] = useState("");
  const [father, setFather] = useState("");
  const [mother, setMother] = useState("");
  const [saving, setSaving] = useState(false);
  const fatherRef = useRef<HTMLInputElement>(null);

  const { data: classes = [] } = useQuery({
    queryKey: ["pp-classes"],
    queryFn: async () => {
      const { data, error } = await supabase.from("students")
        .select("class_id, father_phone, mother_phone, classes(name)").eq("enrollment_status", "active");
      if (error) throw error;
      const m = new Map<string, { id: string; name: string; total: number; done: number }>();
      for (const r of (data ?? []) as any[]) {
        if (!r.class_id) continue;
        const c = m.get(r.class_id) ?? { id: r.class_id, name: r.classes?.name ?? "—", total: 0, done: 0 };
        c.total++; if (r.father_phone || r.mother_phone) c.done++;
        m.set(r.class_id, c);
      }
      return [...m.values()].sort((a, b) => a.name.localeCompare(b.name, "ar"));
    },
  });

  const { data: students = [] } = useQuery({
    queryKey: ["pp-students", classId],
    enabled: !!classId,
    queryFn: async () => {
      const { data, error } = await supabase.from("students").select("id, full_name, father_phone, mother_phone")
        .eq("class_id", classId).eq("enrollment_status", "active").order("full_name");
      if (error) throw error;
      return (data ?? []) as Stu[];
    },
  });

  const cur = students[idx];
  useEffect(() => {
    setFather(cur?.father_phone ?? ""); setMother(cur?.mother_phone ?? "");
  }, [cur?.id]);

  const filtered = useMemo(
    () => students.map((s, i) => ({ s, i })).filter(({ s }) => !q || s.full_name.includes(q.trim())),
    [students, q],
  );

  async function save(goNext: boolean) {
    if (!cur) return;
    const f = normalizeDzPhone(father), m = normalizeDzPhone(mother);
    if (f === null) return toast.error("رقم الأب غير صحيح (مثال: 0661234567)");
    if (m === null) return toast.error("رقم الأم غير صحيح (مثال: 0551234567)");
    const changed = f !== (cur.father_phone ?? "") || m !== (cur.mother_phone ?? "");
    if (changed) {
      setSaving(true);
      const { error } = await supabase.from("students")
        .update({ father_phone: f || null, mother_phone: m || null }).eq("id", cur.id);
      setSaving(false);
      if (error) return toast.error(error.message);
      qc.setQueryData<Stu[]>(["pp-students", classId], (old) =>
        old?.map((s) => (s.id === cur.id ? { ...s, father_phone: f || null, mother_phone: m || null } : s)));
      qc.invalidateQueries({ queryKey: ["pp-classes"] });
      toast.success("تم الحفظ", { duration: 1000 });
    }
    if (goNext && idx < students.length - 1) { setIdx(idx + 1); setTimeout(() => fatherRef.current?.focus(), 50); }
  }

  if (!classId) {
    return (
      <div dir="rtl" className="mx-auto max-w-md space-y-3 p-3">
        <h1 className="text-xl font-bold">أرقام هواتف الأولياء</h1>
        <p className="text-sm text-muted-foreground">اختر القسم للبدء</p>
        <div className="grid gap-2">
          {classes.map((c) => (
            <button key={c.id} onClick={() => { setClassId(c.id); setIdx(0); setQ(""); }}
              className="flex items-center justify-between rounded-xl border bg-card p-4 text-start active:bg-accent">
              <span className="font-medium">{c.name}</span>
              <span className={`rounded-full px-2 py-0.5 text-xs ${c.done === c.total ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"}`}>
                {c.done}/{c.total}
              </span>
            </button>
          ))}
        </div>
      </div>
    );
  }

  const className = classes.find((c) => c.id === classId)?.name;
  const doneCount = students.filter((s) => s.father_phone || s.mother_phone).length;

  return (
    <div dir="rtl" className="mx-auto max-w-md space-y-3 p-3 pb-28">
      <div className="flex items-center justify-between">
        <Button variant="ghost" size="sm" onClick={() => setClassId("")}><ChevronRight className="size-4" /> الأقسام</Button>
        <span className="text-sm text-muted-foreground">{className} · {doneCount}/{students.length}</span>
      </div>

      {cur && (
        <div className="space-y-4 rounded-2xl border bg-card p-4 shadow-sm">
          <div className="text-center">
            <div className="text-xs text-muted-foreground">التلميذ {idx + 1} من {students.length}</div>
            <div className="mt-1 text-lg font-bold leading-snug">{cur.full_name}</div>
          </div>
          <label className="block space-y-1">
            <span className="flex items-center gap-1 text-sm font-medium"><Phone className="size-4" /> هاتف الأب</span>
            <Input ref={fatherRef} type="tel" inputMode="tel" dir="ltr" placeholder="06xxxxxxxx" value={father}
              onChange={(e) => setFather(e.target.value)} className="h-12 text-center text-lg tracking-wider"
              enterKeyHint="next" onKeyDown={(e) => { if (e.key === "Enter") (document.getElementById("mother-in") as HTMLInputElement)?.focus(); }} />
          </label>
          <label className="block space-y-1">
            <span className="flex items-center gap-1 text-sm font-medium"><Phone className="size-4" /> هاتف الأم</span>
            <Input id="mother-in" type="tel" inputMode="tel" dir="ltr" placeholder="05xxxxxxxx" value={mother}
              onChange={(e) => setMother(e.target.value)} className="h-12 text-center text-lg tracking-wider"
              enterKeyHint="done" onKeyDown={(e) => { if (e.key === "Enter") save(true); }} />
          </label>
        </div>
      )}

      <div className="relative">
        <Search className="absolute end-3 top-3 size-4 text-muted-foreground" />
        <Input placeholder="ابحث عن تلميذ..." value={q} onChange={(e) => setQ(e.target.value)} className="pe-9" />
      </div>
      <div className="divide-y rounded-xl border bg-card">
        {filtered.map(({ s, i }) => (
          <button key={s.id} onClick={() => setIdx(i)}
            className={`flex w-full items-center justify-between p-3 text-start text-sm ${i === idx ? "bg-accent" : ""}`}>
            <span>{i + 1}. {s.full_name}</span>
            {(s.father_phone || s.mother_phone) && <Check className="size-4 text-primary" />}
          </button>
        ))}
      </div>

      <div className="fixed inset-x-0 bottom-0 z-20 border-t bg-background/95 p-3 backdrop-blur">
        <div className="mx-auto flex max-w-md gap-2">
          <Button variant="outline" className="h-12 flex-1" disabled={idx === 0 || saving} onClick={async () => { await save(false); setIdx(idx - 1); }}>
            <ChevronRight className="size-5" /> السابق
          </Button>
          <Button className="h-12 flex-[2]" disabled={saving} onClick={() => save(true)}>
            حفظ والتالي <ChevronLeft className="size-5" />
          </Button>
        </div>
      </div>
    </div>
  );
}
