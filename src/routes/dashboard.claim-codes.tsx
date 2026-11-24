import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { QRCodeSVG } from "qrcode.react";
import { Printer, RefreshCw, Ban, Wand2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export const Route = createFileRoute("/dashboard/claim-codes")({
  head: () => ({
    meta: [
      { title: "رموز تفعيل الحسابات — إداروم" },
      { name: "description", content: "توليد رموز ربط الحسابات للتلاميذ والأساتذة وطباعة القصاصات." },
      { property: "og:title", content: "رموز تفعيل الحسابات — إداروم" },
      { property: "og:description", content: "قصاصات ورقية برمز QR لتفعيل الحسابات." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ClaimCodesPage,
});

type Tok = {
  id: string; code: string; kind: "student" | "teacher"; status: string; expires_at: string; used_at: string | null;
  students: { full_name: string; class_id: string | null; classes: { name: string } | null } | null;
  teacher_directory: { full_name: string; subject: string } | null;
};
const ST: Record<string, string> = { valid: "صالح", used: "مستخدم", revoked: "ملغى" };

function ClaimCodesPage() {
  const qc = useQueryClient();
  const [kind, setKind] = useState<"student" | "teacher">("student");
  const [classId, setClassId] = useState("all");
  const [status, setStatus] = useState("valid");
  const [busy, setBusy] = useState(false);
  const origin = typeof window !== "undefined" ? window.location.origin : "";

  const { data: classes = [] } = useQuery({
    queryKey: ["classes-min"],
    queryFn: async () => (await supabase.from("classes").select("id, name").order("name")).data ?? [],
  });
  const { data: tokens = [], isLoading } = useQuery({
    queryKey: ["claim-tokens", kind],
    queryFn: async (): Promise<Tok[]> => {
      const { data, error } = await supabase.from("account_claim_tokens")
        .select("id, code, kind, status, expires_at, used_at, students(full_name, class_id, classes(name)), teacher_directory(full_name, subject)")
        .eq("kind", kind).order("created_at", { ascending: false }).limit(2000);
      if (error) throw error;
      return (data ?? []) as unknown as Tok[];
    },
  });

  const rows = useMemo(() => tokens
    .filter((t) => status === "all" || t.status === status)
    .filter((t) => kind === "teacher" || classId === "all" || t.students?.class_id === classId)
    .sort((a, b) => nameOf(a).localeCompare(nameOf(b), "ar")), [tokens, status, classId, kind]);

  const refresh = () => qc.invalidateQueries({ queryKey: ["claim-tokens"] });

  async function generate() {
    setBusy(true);
    const { data, error } = await supabase.rpc("issue_claim_tokens", { _kind: kind, _class: kind === "student" && classId !== "all" ? classId : undefined });
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(data ? `تم توليد ${data} رمز جديد` : "لا يوجد من يحتاج رمزاً جديداً (الكل مرتبط أو لديه رمز صالح)");
    refresh();
  }
  async function revoke(t: Tok, reissue: boolean) {
    if (!confirm(reissue ? "إلغاء هذا الرمز وتوليد رمز بديل؟" : "إلغاء هذا الرمز نهائياً؟")) return;
    const { data, error } = await supabase.rpc("revoke_claim_token", { _id: t.id, _reissue: reissue });
    if (error) return toast.error(error.message);
    toast.success(reissue ? `الرمز الجديد: ${data}` : "تم الإلغاء");
    refresh();
  }
  const printable = rows.filter((t) => t.status === "valid");

  return (
    <div className="space-y-4">
      <div className="print:hidden space-y-4">
        <PageHeader title="رموز تفعيل الحسابات" description="ولّد رمزاً لكل تلميذ أو أستاذ، اطبع القصاصات، وسلّمها لأصحابها ليربطوا حساباتهم بأنفسهم." />
        <Card><CardContent className="grid grid-cols-1 gap-3 pt-6 sm:grid-cols-2 lg:grid-cols-4">
          <Select value={kind} onValueChange={(v) => setKind(v as "student" | "teacher")}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent><SelectItem value="student">التلاميذ</SelectItem><SelectItem value="teacher">الأساتذة</SelectItem></SelectContent>
          </Select>
          {kind === "student" && (
            <Select value={classId} onValueChange={setClassId}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value="all">كل الأقسام</SelectItem>{classes.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</SelectContent>
            </Select>
          )}
          <Select value={status} onValueChange={setStatus}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent><SelectItem value="valid">الصالحة</SelectItem><SelectItem value="used">المستخدمة</SelectItem><SelectItem value="revoked">الملغاة</SelectItem><SelectItem value="all">الكل</SelectItem></SelectContent>
          </Select>
          <div className="flex gap-2">
            <Button className="flex-1 gap-1" disabled={busy} onClick={generate}><Wand2 className="h-4 w-4" /> توليد</Button>
            <Button variant="outline" className="flex-1 gap-1" disabled={!printable.length} onClick={() => window.print()}><Printer className="h-4 w-4" /> طباعة ({printable.length})</Button>
          </div>
        </CardContent></Card>
        {kind === "teacher" && <p className="text-xs text-muted-foreground">تُولَّد رموز الأساتذة فقط لمن ليس له حساب مرتبط بعد في دليل الأساتذة.</p>}
        {isLoading ? <p>جارٍ التحميل…</p> : rows.length === 0 ? <p className="text-muted-foreground">لا توجد رموز. اضغط «توليد».</p> : (
          <div className="space-y-2">
            {rows.map((t) => (
              <div key={t.id} className="flex flex-col gap-2 rounded-xl border bg-card p-3 sm:flex-row sm:items-center sm:justify-between">
                <div className="min-w-0">
                  <p className="font-medium break-words">{nameOf(t)}</p>
                  <p className="text-xs text-muted-foreground">{detailOf(t)} · <span dir="ltr" className="font-mono">{t.code}</span></p>
                </div>
                <div className="flex items-center gap-2">
                  <Badge variant={t.status === "valid" ? "default" : "secondary"}>{ST[t.status]}</Badge>
                  {t.status === "valid" && <>
                    <Button size="sm" variant="outline" className="gap-1" onClick={() => revoke(t, true)}><RefreshCw className="h-3.5 w-3.5" /> بديل</Button>
                    <Button size="sm" variant="ghost" className="gap-1 text-destructive" onClick={() => revoke(t, false)}><Ban className="h-3.5 w-3.5" /> إلغاء</Button>
                  </>}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="hidden print:grid print:grid-cols-2 print:gap-0" dir="rtl">
        {printable.map((t) => (
          <div key={t.id} className="break-inside-avoid border border-dashed border-foreground/50 p-3 text-[11px] leading-snug">
            <p className="text-center font-bold">ثانوية تقي الدين ابن تيمية — تفعيل حسابك</p>
            <p className="mt-1 text-center text-sm font-bold">{nameOf(t)}</p>
            <p className="text-center">{detailOf(t)}</p>
            <div className="mt-2 flex items-start justify-around gap-2">
              <div className="text-center">
                <QRCodeSVG value={`${origin}/claim?code=${t.code}`} size={84} />
                <p className="mt-1">1. امسح لربط الحساب</p>
              </div>
              <div className="text-center">
                <QRCodeSVG value={`${origin}/`} size={84} />
                <p className="mt-1">2. ثبّت التطبيق</p>
              </div>
            </div>
            <p dir="ltr" className="mt-2 text-center font-mono text-base font-bold tracking-widest">{t.code}</p>
            <p className="mt-1">امسح الرمز الأول أو افتح <span dir="ltr">{origin}/claim</span> واكتب الرمز، سجّل الدخول بـ Google أو Apple أو البريد، ثم اضغط «تأكيد الربط». الرمز لمرة واحدة، لا تشاركه.</p>
            <p className="mt-1 text-[10px]">لتثبيت التطبيق: افتح الرابط ثم «إضافة إلى الشاشة الرئيسية» من قائمة المتصفح. صالح حتى {t.expires_at.slice(0, 10)}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
function nameOf(t: Tok) { return t.students?.full_name ?? t.teacher_directory?.full_name ?? "—"; }
function detailOf(t: Tok) { return t.kind === "student" ? (t.students?.classes?.name ?? "") : (t.teacher_directory?.subject ?? ""); }
