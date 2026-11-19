import { useState, type FormEvent } from "react";
import { toast } from "sonner";
import { Mail, Link2 } from "lucide-react";
import { z } from "zod";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";

const emailSchema = z.string().trim().email("بريد إلكتروني غير صالح").max(255);

/** Lets any signed-in user change their sign-in email and see which providers are linked. */
export function AccountLinkCard() {
  const { user } = useAuth();
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const providers = new Set((user?.identities ?? []).map((i) => i.provider));

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const parsed = emailSchema.safeParse(email);
    if (!parsed.success) return toast.error(parsed.error.issues[0].message);
    if (parsed.data.toLowerCase() === user?.email?.toLowerCase()) return toast.error("هذا هو بريدك الحالي");
    setBusy(true);
    const { error } = await supabase.auth.updateUser(
      { email: parsed.data },
      { emailRedirectTo: `${window.location.origin}/login` },
    );
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success("أرسلنا رابط تأكيد إلى البريد الجديد؛ افتحه لإتمام التغيير.");
    setEmail("");
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 font-display">
          <Link2 className="h-5 w-5" /> البريد وربط Google / Apple
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-2 text-sm">
          <span className="text-muted-foreground">طرق الدخول المفعّلة:</span>
          <Badge variant="outline">البريد وكلمة المرور</Badge>
          {providers.has("google") && <Badge>Google</Badge>}
          {providers.has("apple") && <Badge>Apple</Badge>}
        </div>
        <ol className="list-decimal space-y-1 pe-5 text-sm text-muted-foreground">
          <li>ضع هنا بريد Gmail أو Apple الخاص بك وأكّده من الرسالة التي تصلك.</li>
          <li>بعدها اضغط «المتابعة باستخدام Google» أو «Apple» في صفحة الدخول بنفس البريد.</li>
          <li>يُربط الحساب تلقائياً وتبقى كلمة المرور صالحة أيضاً.</li>
        </ol>
        <form onSubmit={submit} className="space-y-2">
          <Label htmlFor="new-email">البريد الإلكتروني الجديد</Label>
          <p className="text-xs text-muted-foreground" dir="ltr">{user?.email}</p>
          <div className="flex flex-col gap-2 sm:flex-row">
            <Input id="new-email" type="email" dir="ltr" inputMode="email" autoComplete="email"
              value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@gmail.com" />
            <Button type="submit" disabled={busy} className="gap-2">
              <Mail className="h-4 w-4" /> {busy ? "جارٍ الإرسال..." : "تغيير البريد"}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
