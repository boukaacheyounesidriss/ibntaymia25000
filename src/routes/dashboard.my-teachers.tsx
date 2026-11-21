import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { ExternalLink } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { friendlyError } from "@/lib/friendly-error";
import { POST_KINDS, WEEKDAYS, MEETING_TARGETS, MEETING_STATUS, safeLink } from "@/lib/teacher-hub";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export const Route = createFileRoute("/dashboard/my-teachers")({
  component: MyTeachers,
  head: () => ({
    meta: [
      { title: "الأساتذة والدروس — إداروم" },
      { name: "description", content: "أساتذة القسم وأوقات استقبالهم، دروسهم وواجباتهم، وحجز المواعيد." },
      { property: "og:title", content: "الأساتذة والدروس — إداروم" },
      { property: "og:description", content: "فضاء الولي والتلميذ للتواصل مع الأساتذة." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

type T = { student_id: string; student_name: string; class_name: string; teacher_id: string; teacher_name: string; subject: string; is_head: boolean; reception: { weekday: number; start: string; end: string; place: string | null }[] };

function MyTeachers() {
  const { hasRole } = useAuth();
  const isParent = hasRole("parent");
  const { data: rows = [] } = useQuery({
    queryKey: ["my-children-teachers"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("my_children_teachers");
      if (error) throw error;
      return (data ?? []) as unknown as T[];
    },
  });
  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <h1 className="font-display text-2xl font-bold">الأساتذة والدروس</h1>
      <Tabs defaultValue="teachers">
        <TabsList className={`grid w-full ${isParent ? "grid-cols-3" : "grid-cols-2"}`}>
          <TabsTrigger value="teachers">الأساتذة</TabsTrigger>
          <TabsTrigger value="feed">الدروس والواجبات</TabsTrigger>
          {isParent && <TabsTrigger value="book">المواعيد</TabsTrigger>}
        </TabsList>
        <TabsContent value="teachers" className="mt-4 space-y-2">
          {!rows.length && <p className="text-sm text-muted-foreground">لا توجد بيانات أساتذة مرتبطة بحسابك بعد.</p>}
          {rows.map((r) => (
            <Card key={r.student_id + r.teacher_id + r.subject}><CardContent className="space-y-1 pt-4 text-sm">
              <p className="font-semibold">{r.teacher_name} {r.is_head && <Badge className="ms-1">الأستاذ الرئيسي</Badge>}</p>
              <p className="text-muted-foreground">{r.subject} · {r.class_name}{isParent ? ` · ${r.student_name}` : ""}</p>
              {r.reception.length ? r.reception.map((h, i) => (
                <p key={i}>الاستقبال: {WEEKDAYS[h.weekday]} <span className="ltr">{h.start}–{h.end}</span>{h.place ? ` · ${h.place}` : ""}</p>
              )) : <p className="text-xs text-muted-foreground">لم يحدد وقت استقبال بعد</p>}
            </CardContent></Card>
          ))}
        </TabsContent>
        <TabsContent value="feed" className="mt-4"><Feed /></TabsContent>
        {isParent && <TabsContent value="book" className="mt-4"><Book teachers={rows} /></TabsContent>}
      </Tabs>
    </div>
  );
}

function Feed() {
  const { data: posts = [] } = useQuery({
    queryKey: ["class-feed"],
    queryFn: async () => (await supabase.from("teacher_posts").select("id, kind, title, body, link_url, due_date, created_at, classes(name)").order("created_at", { ascending: false }).limit(60)).data ?? [],
  });
  if (!posts.length) return <p className="text-sm text-muted-foreground">لا منشورات بعد.</p>;
  return (
    <div className="space-y-2">
      {posts.map((p) => {
        const link = safeLink(p.link_url);
        return (
          <Card key={p.id}><CardContent className="space-y-1 pt-4 text-sm">
            <p className="font-semibold"><Badge variant="secondary" className="me-1">{POST_KINDS[p.kind] ?? p.kind}</Badge>{p.title}</p>
            <p className="text-xs text-muted-foreground">{(p.classes as { name: string } | null)?.name}{p.due_date ? ` · ${p.due_date}` : ""}</p>
            {p.body && <p className="whitespace-pre-wrap">{p.body}</p>}
            {link && <a href={link} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-primary underline"><ExternalLink className="h-3 w-3" />فتح الرابط</a>}
          </CardContent></Card>
        );
      })}
    </div>
  );
}

function Book({ teachers }: { teachers: T[] }) {
  const { user } = useAuth();
  const qc = useQueryClient();
  const kids = [...new Map(teachers.map((t) => [t.student_id, t.student_name])).entries()];
  const [f, setF] = useState({ student_id: "", target_kind: "teacher", teacher_id: "", date: "", slot: "", message: "" });
  const sid = f.student_id || kids[0]?.[0] || "";
  const { data: mine = [] } = useQuery({
    queryKey: ["my-meetings", user?.id],
    enabled: !!user,
    queryFn: async () => (await supabase.from("meeting_requests").select("id, target_kind, preferred_date, preferred_slot, status, review_note").eq("parent_user_id", user!.id).order("created_at", { ascending: false })).data ?? [],
  });
  async function send() {
    if (!sid) return toast.error("لا يوجد تلميذ مرتبط بحسابك");
    if (f.target_kind === "teacher" && !f.teacher_id) return toast.error("اختر الأستاذ");
    if (!f.message.trim()) return toast.error("اكتب موضوع اللقاء");
    const { error } = await supabase.from("meeting_requests").insert({
      parent_user_id: user!.id, student_id: sid, target_kind: f.target_kind,
      target_teacher_id: f.target_kind === "teacher" ? f.teacher_id : null,
      preferred_date: f.date || null, preferred_slot: f.slot || null, message: f.message.trim(),
    });
    if (error) return toast.error(friendlyError(error));
    toast.success("أُرسل طلب الموعد");
    setF({ ...f, message: "" });
    qc.invalidateQueries({ queryKey: ["my-meetings"] });
  }
  const tOpts = teachers.filter((t) => t.student_id === sid);
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader><CardTitle className="text-base">طلب موعد</CardTitle></CardHeader>
        <CardContent className="space-y-2">
          {kids.length > 1 && (
            <Select value={sid} onValueChange={(v) => setF({ ...f, student_id: v, teacher_id: "" })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{kids.map(([id, n]) => <SelectItem key={id} value={id}>{n}</SelectItem>)}</SelectContent>
            </Select>
          )}
          <Select value={f.target_kind} onValueChange={(v) => setF({ ...f, target_kind: v })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>{Object.entries(MEETING_TARGETS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}</SelectContent>
          </Select>
          {f.target_kind === "teacher" && (
            <Select value={f.teacher_id} onValueChange={(v) => setF({ ...f, teacher_id: v })}>
              <SelectTrigger><SelectValue placeholder="الأستاذ" /></SelectTrigger>
              <SelectContent>{tOpts.map((t) => <SelectItem key={t.teacher_id + t.subject} value={t.teacher_id}>{t.teacher_name} — {t.subject}</SelectItem>)}</SelectContent>
            </Select>
          )}
          <div className="grid grid-cols-2 gap-2">
            <Input type="date" value={f.date} onChange={(e) => setF({ ...f, date: e.target.value })} />
            <Input placeholder="الوقت المفضل" value={f.slot} onChange={(e) => setF({ ...f, slot: e.target.value })} />
          </div>
          <Textarea placeholder="موضوع اللقاء باختصار" value={f.message} onChange={(e) => setF({ ...f, message: e.target.value })} />
          <Button className="w-full" onClick={send}>إرسال الطلب</Button>
        </CardContent>
      </Card>
      {mine.map((m) => (
        <Card key={m.id}><CardContent className="flex items-center justify-between pt-4 text-sm">
          <span>{MEETING_TARGETS[m.target_kind] ?? m.target_kind} · {m.preferred_date ?? ""} {m.review_note ? `· ${m.review_note}` : ""}</span>
          <Badge variant="outline">{MEETING_STATUS[m.status]}</Badge>
        </CardContent></Card>
      ))}
    </div>
  );
}
