import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { friendlyError } from "@/lib/friendly-error";
import { POST_KINDS, WEEKDAYS, MEETING_STATUS, safeLink } from "@/lib/teacher-hub";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export const Route = createFileRoute("/dashboard/teacher-space")({
  component: TeacherSpace,
  head: () => ({
    meta: [
      { title: "فضاء الأستاذ — إداروم" },
      { name: "description", content: "نشر الدروس والملخصات والواجبات، وأوقات استقبال الأولياء، ومواعيدهم." },
      { property: "og:title", content: "فضاء الأستاذ — إداروم" },
      { property: "og:description", content: "فضاء الأستاذ البيداغوجي لأقسامه." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

function TeacherSpace() {
  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <h1 className="font-display text-2xl font-bold">فضاء الأستاذ</h1>
      <Tabs defaultValue="posts">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="posts">المنشورات</TabsTrigger>
          <TabsTrigger value="hours">الاستقبال</TabsTrigger>
          <TabsTrigger value="meet">المواعيد</TabsTrigger>
        </TabsList>
        <TabsContent value="posts" className="mt-4"><Posts /></TabsContent>
        <TabsContent value="hours" className="mt-4"><Hours /></TabsContent>
        <TabsContent value="meet" className="mt-4"><Meetings /></TabsContent>
      </Tabs>
    </div>
  );
}

function useMyClasses() {
  const { user } = useAuth();
  return useQuery({
    queryKey: ["my-classes", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data } = await supabase.from("schedule_slots").select("class_id, classes(name)").eq("teacher_id", user!.id).eq("is_active", true);
      const m = new Map<string, string>();
      (data ?? []).forEach((r) => m.set(r.class_id, (r.classes as { name: string } | null)?.name ?? ""));
      return [...m].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
    },
  });
}

function Posts() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const { data: classes = [] } = useMyClasses();
  const [f, setF] = useState({ class_id: "", kind: "lesson", title: "", body: "", link_url: "", due_date: "" });
  const { data: posts = [] } = useQuery({
    queryKey: ["my-posts", user?.id],
    enabled: !!user,
    queryFn: async () => (await supabase.from("teacher_posts").select("id, kind, title, body, link_url, due_date, created_at, classes(name)").eq("teacher_id", user!.id).order("created_at", { ascending: false })).data ?? [],
  });
  async function add() {
    if (!f.class_id || !f.title.trim()) return toast.error("اختر القسم واكتب العنوان");
    if (f.link_url && !safeLink(f.link_url)) return toast.error("الرابط غير صالح");
    const { error } = await supabase.from("teacher_posts").insert({
      class_id: f.class_id, kind: f.kind, title: f.title.trim(), body: f.body.trim() || null,
      link_url: safeLink(f.link_url), due_date: f.due_date || null, teacher_id: user!.id,
    });
    if (error) return toast.error(friendlyError(error));
    toast.success("تم النشر لتلاميذ القسم وأوليائهم");
    setF({ ...f, title: "", body: "", link_url: "", due_date: "" });
    qc.invalidateQueries({ queryKey: ["my-posts"] });
  }
  async function del(id: string) {
    if (!confirm("حذف المنشور؟")) return;
    await supabase.from("teacher_posts").delete().eq("id", id);
    qc.invalidateQueries({ queryKey: ["my-posts"] });
  }
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader><CardTitle className="text-base">منشور جديد</CardTitle></CardHeader>
        <CardContent className="space-y-2">
          <div className="grid grid-cols-2 gap-2">
            <Select value={f.class_id} onValueChange={(v) => setF({ ...f, class_id: v })}>
              <SelectTrigger><SelectValue placeholder="القسم" /></SelectTrigger>
              <SelectContent>{classes.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</SelectContent>
            </Select>
            <Select value={f.kind} onValueChange={(v) => setF({ ...f, kind: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{Object.entries(POST_KINDS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <Input placeholder="العنوان" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} />
          <Textarea placeholder="المحتوى" rows={4} value={f.body} onChange={(e) => setF({ ...f, body: e.target.value })} />
          <Input dir="ltr" placeholder="رابط (اختياري) https://..." value={f.link_url} onChange={(e) => setF({ ...f, link_url: e.target.value })} />
          {(f.kind === "homework" || f.kind === "event") && (
            <label className="block text-sm">تاريخ التسليم / الحدث<Input type="date" value={f.due_date} onChange={(e) => setF({ ...f, due_date: e.target.value })} /></label>
          )}
          <Button className="w-full" onClick={add}>نشر</Button>
        </CardContent>
      </Card>
      {posts.map((p) => (
        <Card key={p.id}><CardContent className="space-y-1 pt-4 text-sm">
          <div className="flex items-center justify-between gap-2">
            <p className="font-semibold"><Badge variant="secondary" className="me-1">{POST_KINDS[p.kind] ?? p.kind}</Badge>{p.title}</p>
            <Button size="icon" variant="ghost" onClick={() => del(p.id)} aria-label="حذف"><Trash2 className="h-4 w-4" /></Button>
          </div>
          <p className="text-xs text-muted-foreground">{(p.classes as { name: string } | null)?.name}{p.due_date ? ` · ${p.due_date}` : ""}</p>
          {p.body && <p className="whitespace-pre-wrap">{p.body}</p>}
        </CardContent></Card>
      ))}
    </div>
  );
}

function Hours() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const [f, setF] = useState({ weekday: "0", start_time: "10:00", end_time: "11:00", place: "" });
  const { data: rows = [] } = useQuery({
    queryKey: ["my-reception", user?.id],
    enabled: !!user,
    queryFn: async () => (await supabase.from("teacher_reception_hours").select("*").eq("teacher_id", user!.id).order("weekday")).data ?? [],
  });
  const { data: free = [] } = useQuery({
    queryKey: ["my-busy", user?.id],
    enabled: !!user,
    queryFn: async () => (await supabase.from("schedule_slots").select("weekday, start_time, end_time").eq("teacher_id", user!.id).eq("is_active", true)).data ?? [],
  });
  const clash = free.some((s) => s.weekday === Number(f.weekday) && s.start_time.slice(0, 5) < f.end_time && f.start_time < s.end_time.slice(0, 5));
  async function add() {
    if (f.end_time <= f.start_time) return toast.error("وقت النهاية يجب أن يكون بعد البداية");
    if (clash) return toast.error("هذا الوقت يتعارض مع حصة في جدولك");
    const { error } = await supabase.from("teacher_reception_hours").insert({ teacher_id: user!.id, weekday: Number(f.weekday), start_time: f.start_time, end_time: f.end_time, place: f.place || null });
    if (error) return toast.error(friendlyError(error));
    toast.success("أُضيف وقت الاستقبال ويظهر لأولياء تلاميذك");
    qc.invalidateQueries({ queryKey: ["my-reception"] });
  }
  return (
    <Card>
      <CardHeader><CardTitle className="text-base">أوقات استقبال الأولياء</CardTitle></CardHeader>
      <CardContent className="space-y-3">
        <p className="text-xs text-muted-foreground">اختر وقتاً من ساعات فراغك في جدول الإسناد؛ يمنع النظام الأوقات المتعارضة مع حصصك.</p>
        <div className="grid grid-cols-2 gap-2">
          <Select value={f.weekday} onValueChange={(v) => setF({ ...f, weekday: v })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>{WEEKDAYS.slice(0, 5).map((d, i) => <SelectItem key={i} value={String(i)}>{d}</SelectItem>)}</SelectContent>
          </Select>
          <Input placeholder="المكان (اختياري)" value={f.place} onChange={(e) => setF({ ...f, place: e.target.value })} />
          <Input type="time" value={f.start_time} onChange={(e) => setF({ ...f, start_time: e.target.value })} />
          <Input type="time" value={f.end_time} onChange={(e) => setF({ ...f, end_time: e.target.value })} />
        </div>
        {clash && <p className="text-xs text-destructive">يتعارض مع حصة لديك.</p>}
        <Button className="w-full" onClick={add}>إضافة</Button>
        <ul className="divide-y">
          {rows.map((r) => (
            <li key={r.id} className="flex items-center justify-between py-2 text-sm">
              <span>{WEEKDAYS[r.weekday]} <span className="ltr">{r.start_time.slice(0, 5)}–{r.end_time.slice(0, 5)}</span> {r.place ? `· ${r.place}` : ""}</span>
              <Button size="icon" variant="ghost" aria-label="حذف" onClick={async () => { await supabase.from("teacher_reception_hours").delete().eq("id", r.id); qc.invalidateQueries({ queryKey: ["my-reception"] }); }}><Trash2 className="h-4 w-4" /></Button>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}

function Meetings() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const { data: rows = [] } = useQuery({
    queryKey: ["teacher-meetings", user?.id],
    enabled: !!user,
    queryFn: async () => (await supabase.from("meeting_requests").select("id, preferred_date, preferred_slot, message, status, review_note, students(full_name)").eq("target_teacher_id", user!.id).order("created_at", { ascending: false })).data ?? [],
  });
  async function set(id: string, status: string) {
    const note = status === "rejected" ? prompt("سبب الرفض أو اقتراح موعد آخر:") ?? "" : "";
    const { error } = await supabase.from("meeting_requests").update({ status, review_note: note || null, reviewed_by: user!.id, reviewed_at: new Date().toISOString() }).eq("id", id);
    if (error) return toast.error(friendlyError(error));
    qc.invalidateQueries({ queryKey: ["teacher-meetings"] });
  }
  if (!rows.length) return <p className="text-sm text-muted-foreground">لا توجد طلبات مواعيد.</p>;
  return (
    <div className="space-y-2">
      {rows.map((r) => (
        <Card key={r.id}><CardContent className="space-y-2 pt-4 text-sm">
          <div className="flex justify-between"><p className="font-semibold">ولي: {(r.students as { full_name: string } | null)?.full_name}</p><Badge variant="outline">{MEETING_STATUS[r.status]}</Badge></div>
          <p className="text-muted-foreground">{r.preferred_date ?? ""} {r.preferred_slot ?? ""}</p>
          {r.message && <p>{r.message}</p>}
          {r.status === "pending" && (
            <div className="flex gap-2"><Button size="sm" onClick={() => set(r.id, "approved")}>قبول</Button><Button size="sm" variant="outline" onClick={() => set(r.id, "rejected")}>رفض / تأجيل</Button></div>
          )}
          {r.status === "approved" && <Button size="sm" variant="outline" onClick={() => set(r.id, "done")}>تم اللقاء</Button>}
        </CardContent></Card>
      ))}
    </div>
  );
}
