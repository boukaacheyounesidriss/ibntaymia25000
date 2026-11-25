import { useRef, useState } from "react";
import { Camera, Upload, X, Link as LinkIcon, Send } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { POST_KINDS, safeLink } from "@/lib/teacher-hub";
import { friendlyError } from "@/lib/friendly-error";
import { LESSON_ACCEPT, LESSON_BUCKET, prepareLessonFile, fileSize, type LessonAttachment } from "@/lib/lesson-files";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export function TeacherPostComposer({ classes, onPublished }: { classes: { id: string; name: string }[]; onPublished: () => void }) {
  const { user } = useAuth();
  const [form, setForm] = useState({ class_id: "", kind: "lesson", title: "", body: "", link_url: "", due_date: "" });
  const [files, setFiles] = useState<File[]>([]);
  const [compress, setCompress] = useState(true);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState("");
  const picker = useRef<HTMLInputElement>(null);
  const camera = useRef<HTMLInputElement>(null);
  function selectFiles(list: FileList | null) { if (list) setFiles((old) => [...old, ...Array.from(list)]); }
  async function publish() {
    if (!user || busy) return;
    if (!form.class_id || !form.title.trim()) return toast.error("اختر القسم واكتب العنوان");
    if (form.link_url && !safeLink(form.link_url)) return toast.error("الرابط غير صالح");
    const postId = crypto.randomUUID();
    const uploaded: string[] = [];
    const attachments: LessonAttachment[] = [];
    setBusy(true);
    try {
      for (const [index, file] of files.entries()) {
        setProgress(`تجهيز ورفع الملف ${index + 1} من ${files.length}`);
        const ready = await prepareLessonFile(file, compress);
        const suffix = ready.name.split(".").pop()?.toLowerCase() ?? "pdf";
        const path = `${user.id}/${postId}/${crypto.randomUUID()}.${suffix}`;
        const { error } = await supabase.storage.from(LESSON_BUCKET).upload(path, ready, { contentType: ready.type, upsert: false });
        if (error) throw error;
        uploaded.push(path);
        attachments.push({ path, name: ready.name, type: ready.type, size: ready.size });
      }
      setProgress("جارٍ نشر الدرس…");
      const { error } = await supabase.from("teacher_posts").insert({
        id: postId, teacher_id: user.id, class_id: form.class_id, kind: form.kind, title: form.title.trim(),
        body: form.body.trim() || null, link_url: safeLink(form.link_url), due_date: form.due_date || null,
        attachments: attachments.map((a) => ({ ...a })),
      });
      if (error) throw error;
      setForm((old) => ({ ...old, title: "", body: "", link_url: "", due_date: "" }));
      setFiles([]);
      onPublished();
      toast.success("تم النشر لتلاميذ القسم وأوليائهم");
    } catch (error) {
      if (uploaded.length) {
        const cleanup = await supabase.storage.from(LESSON_BUCKET).remove(uploaded);
        if (cleanup.error) toast.warning("تعذّر تنظيف بعض الملفات غير المنشورة؛ أبلغ الإدارة.");
      }
      toast.error(error instanceof Error ? error.message : friendlyError(error));
    } finally { setBusy(false); setProgress(""); }
  }
  return <Card><CardHeader><CardTitle className="text-base">منشور جديد</CardTitle></CardHeader>
    <CardContent><fieldset disabled={busy} className="min-w-0 space-y-3">
      <div className="grid min-w-0 grid-cols-2 gap-2">
        <Select disabled={busy} value={form.class_id} onValueChange={(v) => setForm({ ...form, class_id: v })}><SelectTrigger aria-label="القسم"><SelectValue placeholder="القسم" /></SelectTrigger><SelectContent>{classes.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</SelectContent></Select>
        <Select disabled={busy} value={form.kind} onValueChange={(v) => setForm({ ...form, kind: v })}><SelectTrigger aria-label="نوع المنشور"><SelectValue /></SelectTrigger><SelectContent>{Object.entries(POST_KINDS).map(([k, v]) => <SelectItem key={k} value={k}>{v}</SelectItem>)}</SelectContent></Select>
      </div>
      <Input aria-label="عنوان الدرس" placeholder="العنوان" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
      <Textarea aria-label="محتوى الدرس" placeholder="المحتوى" rows={4} value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} />
      <div className="grid grid-cols-2 gap-2">
        <Button type="button" variant="outline" className="h-11" onClick={() => picker.current?.click()}><Upload /> رفع ملفات</Button>
        <Button type="button" variant="outline" className="h-11" onClick={() => camera.current?.click()}><Camera /> تصوير</Button>
      </div>
      <input ref={picker} className="hidden" type="file" accept={LESSON_ACCEPT} multiple aria-label="ملفات الدرس" onChange={(e) => { selectFiles(e.target.files); e.target.value = ""; }} />
      <input ref={camera} className="hidden" type="file" accept="image/*" capture="environment" aria-label="تصوير الدرس" onChange={(e) => { selectFiles(e.target.files); e.target.value = ""; }} />
      {!!files.length && <div className="space-y-2">
        {files.map((file, index) => <div key={`${index}-${file.name}`} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-b border-border pb-2"><div className="min-w-0"><p className="truncate text-sm" title={file.name}>{file.name}</p><p className="text-xs text-muted-foreground" dir="ltr">{fileSize(file.size)}</p></div><Button type="button" size="icon" variant="ghost" aria-label={`إزالة ${file.name}`} onClick={() => setFiles((old) => old.filter((_, i) => i !== index))}><X /></Button></div>)}
        <label className="flex items-center gap-2 text-sm"><Checkbox checked={compress} onCheckedChange={(v) => setCompress(v === true)} /> تقليل حجم الصور</label>
      </div>}
      <div className="flex min-w-0 items-center gap-2"><LinkIcon className="h-4 w-4 shrink-0 text-muted-foreground" /><Input aria-label="رابط الدرس" dir="ltr" className="min-w-0" placeholder="https://... (اختياري)" value={form.link_url} onChange={(e) => setForm({ ...form, link_url: e.target.value })} /></div>
      {(form.kind === "homework" || form.kind === "event") && <label className="block text-sm">تاريخ التسليم / الحدث<Input type="date" value={form.due_date} onChange={(e) => setForm({ ...form, due_date: e.target.value })} /></label>}
      <Button type="button" className="h-11 w-full" disabled={busy || !classes.length} onClick={publish}><Send />{busy ? progress : "نشر"}</Button>
    </fieldset></CardContent>
  </Card>;
}
