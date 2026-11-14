import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useEffect, useState, type FormEvent } from "react";
import { signInWithIdentifier } from "@/lib/login.functions";
import { useTranslation } from "react-i18next";
import { GraduationCap } from "lucide-react";
import { toast } from "sonner";

import { supabase } from "@/integrations/supabase/client";
import { lovable } from "@/integrations/lovable";
import { useAuth } from "@/lib/use-auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { DemoLoginPanel } from "@/components/DemoLoginPanel";
import appleWhite from "@/assets/apple-sign-in-white.svg";
import appleBlack from "@/assets/apple-sign-in-black.svg";

export const Route = createFileRoute("/login")({
  head: () => ({
    meta: [
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { title: "تسجيل الدخول — إداروم" },
      {
        name: "description",
        content:
          "ادخل إلى منصة إداروم بحسابك المدرسي للوصول إلى لوحة التحكم، إدارة الحضور، الإشعارات والشارات الرقمية.",
      },
      { property: "og:title", content: "تسجيل الدخول — إداروم" },
      {
        property: "og:description",
        content: "صفحة تسجيل الدخول الآمنة لمنصة إداروم — للمعلمين والأولياء والإدارة.",
      },
    ],
  }),
  component: LoginPage,
});

function LoginPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { user, loading } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const signIn = useServerFn(signInWithIdentifier);

  useEffect(() => {
    if (!loading && user) {
      navigate({ to: "/dashboard" });
    }
  }, [user, loading, navigate]);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      const identifier = email.trim();
      // Always resolve + diagnose server-side so the failure reason is precise
      // (unknown account / wrong password / disabled / unconfirmed / no role).
      const tokens = await signIn({ data: { identifier, password } });
      const { error } = await supabase.auth.setSession({
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
      });
      if (error) throw error;
      navigate({ to: "/dashboard" });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err));
    } finally {
      setSubmitting(false);
    }
  };

  const handleSocial = async (provider: "google" | "apple") => {
    setSubmitting(true);
    try {
      const result = await lovable.auth.signInWithOAuth(provider, {
        redirect_uri: window.location.origin + "/login",
      });
      if (result.error) throw result.error;
      if (!result.redirected) {
        const { data, error } = await supabase.auth.getUser();
        if (error) throw error;
        if (data.user) navigate({ to: "/dashboard" });
        setSubmitting(false);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err));
      setSubmitting(false);
    }
  };

  return (
    <div
      className="flex min-h-screen items-center justify-center bg-background px-4 py-10"
      style={{
        backgroundImage:
          "radial-gradient(60% 60% at 50% 0%, color-mix(in oklab, var(--primary) 15%, transparent), transparent 70%)",
      }}
    >
      <div className="absolute right-4 top-4 flex gap-2">
        <LanguageSwitcher />
      </div>
      <div className="w-full max-w-md">
        <Link to="/" className="mb-6 flex items-center justify-center gap-2">
          <span className="grid h-10 w-10 place-items-center rounded-lg bg-primary text-primary-foreground">
            <GraduationCap className="h-5 w-5" />
          </span>
          <span className="text-xl font-bold">{t("brand.name")}</span>
        </Link>

        <Card>
          <CardHeader>
            <h1 className="sr-only">تسجيل الدخول إلى منصة إداروم</h1>
            <CardTitle>{t("auth.welcome_back")}</CardTitle>
            <p className="text-sm text-muted-foreground">{t("auth.auth_subtitle")}</p>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button
              type="button"
              variant="outline"
              className="google-sign-in h-11 w-full"
              onClick={() => void handleSocial("google")}
              disabled={submitting}
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="size-[18px] shrink-0" viewBox="0 0 24 24" aria-hidden="true">
                <path fill="#4285F4" d="M23.49 12.27c0-.79-.07-1.54-.19-2.27H12v4.51h6.47c-.29 1.48-1.14 2.73-2.4 3.58v3h3.86c2.26-2.09 3.56-5.17 3.56-8.82z" />
                <path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.86-3c-1.08.72-2.45 1.16-4.07 1.16-3.13 0-5.78-2.11-6.73-4.96H1.29v3.09C3.26 21.3 7.31 24 12 24z" />
                <path fill="#FBBC05" d="M5.27 14.29c-.25-.72-.38-1.49-.38-2.29s.14-1.57.38-2.29V6.62H1.29C.47 8.24 0 10.06 0 12s.47 3.76 1.29 5.38l3.98-3.09z" />
                <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.31 0 3.26 2.7 1.29 6.62l3.98 3.09c.95-2.85 3.6-4.96 6.73-4.96z" />
              </svg>
              <span>{t("auth.continue_google")}</span>
            </Button>

            <Button
              type="button"
              variant="outline"
              className="apple-sign-in h-11 w-full"
              onClick={() => void handleSocial("apple")}
              disabled={submitting}
            >
              <img src={appleWhite} alt="" className="apple-logo-light" />
              <img src={appleBlack} alt="" className="apple-logo-dark" />
              <span>Continue with Apple</span>
            </Button>

            <div className="relative">
              <div className="absolute inset-0 flex items-center">
                <span className="w-full border-t border-border" />
              </div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-card px-2 text-muted-foreground">{t("auth.or")}</span>
              </div>
            </div>

            <form onSubmit={handleSubmit} className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="email">{t("auth.email")} / اسم المستخدم / رمز الحساب</Label>
                <Input
                  id="email"
                  type="text"
                  autoComplete="username"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="password">{t("auth.password")}</Label>
                <Input
                  id="password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  minLength={6}
                />
              </div>
              <Button type="submit" className="w-full" disabled={submitting}>
                {submitting ? t("auth.signing_in") : t("auth.sign_in")}
              </Button>
              <div className="text-center">
                <Link to="/forgot-password" className="text-xs text-primary hover:underline">
                  نسيت كلمة المرور؟
                </Link>
              </div>
            </form>

            <p className="text-center text-xs text-muted-foreground">
              {t("auth.contact_admin_for_account") ||
                "للحصول على حساب، يرجى التواصل مع إدارة المؤسسة."}
            </p>

            <DemoLoginPanel />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
