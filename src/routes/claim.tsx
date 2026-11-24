import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { KeyRound, ShieldCheck, UserCheck } from "lucide-react";
import { z } from "zod";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { clearPendingClaim, getPendingClaim, normalizeClaimCode, setPendingClaim, CLAIM_CODE_RE } from "@/lib/pending-claim";

export const Route = createFileRoute("/claim")({
  validateSearch: z.object({ code: z.string().optional() }),
  head: () => ({
    meta: [
      { title: "تفعيل وربط الحساب — إداروم" },
      { name: "description", content: "اربط حسابك بملفك في الثانوية باستعمال رمز التفعيل المطبوع على القصاصة." },
      { property: "og:title", content: "تفعيل وربط الحساب — إداروم" },
      { property: "og:description", content: "أدخل رمز التفعيل لربط حسابك بملف التلميذ أو الأستاذ." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ClaimPage,
});

type Preview = { ok: boolean; error?: string; kind?: "student" | "teacher"; name?: string; detail?: string };

function ClaimPage() {
  const { code: urlCode } = Route.useSearch();
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const [code, setCode] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const c = urlCode ? normalizeClaimCode(urlCode) : getPendingClaim();
    if (c) { setCode(c); setPendingClaim(c); }
  }, [urlCode]);

  async function check(e?: React.FormEvent) {
    e?.preventDefault();
    const c = normalizeClaimCode(code);
    if (!CLAIM_CODE_RE.test(c)) return toast.error("الرمز يكون بالشكل TAYM-XXXX-XXXX");
    setPendingClaim(c); setCode(c);
    if (!user) return;
    setBusy(true);
    const { data, error } = await supabase.rpc("preview_claim_token", { _code: c });
    setBusy(false);
    if (error) return toast.error(error.message);
    const p = data as unknown as Preview;
    if (!p?.ok) toast.error(p?.error ?? "رمز غير صالح");
    setPreview(p);
  }

  async function confirm() {
    setBusy(true);
    const { data, error } = await supabase.rpc("claim_account", { _code: code });
    setBusy(false);
    if (error) return toast.error(error.message);
    clearPendingClaim();
    toast.success(`تم ربط حسابك: ${(data as { name?: string })?.name ?? ""}`);
    window.location.href = "/dashboard";
  }

  return (
    <div dir="rtl" className="flex min-h-screen items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardContent className="space-y-5 pt-6">
          <div className="text-center">
            <KeyRound className="mx-auto h-10 w-10 text-primary" />
            <h1 className="mt-2 text-2xl font-bold">تفعيل وربط الحساب</h1>
            <p className="text-sm text-muted-foreground">أدخل الرمز المطبوع على القصاصة التي سلّمتها لك الإدارة.</p>
          </div>

          {!preview?.ok && (
            <form onSubmit={check} className="space-y-3">
              <Input dir="ltr" value={code} onChange={(e) => setCode(e.target.value)} placeholder="TAYM-XXXX-XXXX"
                className="h-12 text-center font-mono text-lg tracking-widest" autoCapitalize="characters" />
              {user ? (
                <Button type="submit" className="h-12 w-full" disabled={busy}>تحقق من الرمز</Button>
              ) : (
                <div className="space-y-2">
                  <p className="rounded-lg bg-muted p-3 text-sm">سجّل الدخول أولاً (Google أو Apple أو البريد)، ثم تعود إلى هذه الصفحة تلقائياً.</p>
                  <Button type="button" className="h-12 w-full" disabled={loading}
                    onClick={() => { const c = normalizeClaimCode(code); if (c) setPendingClaim(c); navigate({ to: "/login" }); }}>
                    تسجيل الدخول للمتابعة
                  </Button>
                </div>
              )}
            </form>
          )}

          {preview?.ok && (
            <div className="space-y-4">
              <div className="rounded-xl border border-primary/40 bg-primary/5 p-4 text-center">
                <UserCheck className="mx-auto h-8 w-8 text-primary" />
                <p className="mt-2">مرحباً! هذا الرمز يخص</p>
                <p className="text-xl font-bold">{preview.name}</p>
                <p className="text-muted-foreground">{preview.kind === "student" ? "القسم" : "المادة"}: {preview.detail}</p>
                <p className="mt-2 font-semibold">هل هذا أنت؟</p>
              </div>
              <p className="text-xs text-muted-foreground">سيُربط حسابك الحالي ({user?.email}) بهذا الملف نهائياً، ولا يمكن استعمال الرمز مرة أخرى.</p>
              <Button className="h-12 w-full gap-2" disabled={busy} onClick={confirm}><ShieldCheck className="h-5 w-5" /> تأكيد الربط</Button>
              <Button variant="ghost" className="w-full" onClick={() => setPreview(null)}>ليس أنا / رمز آخر</Button>
            </div>
          )}
          <p className="text-center text-xs text-muted-foreground"><Link to="/support" className="underline">تحتاج مساعدة؟</Link></p>
        </CardContent>
      </Card>
    </div>
  );
}
