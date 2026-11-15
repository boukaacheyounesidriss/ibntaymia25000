import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/auth/callback")({
  head: () => ({
    meta: [
      { title: "جارٍ إتمام الدخول — إداروم" },
      { name: "description", content: "إتمام تسجيل الدخول إلى منصة إداروم." },
      { property: "og:title", content: "جارٍ إتمام الدخول — إداروم" },
      { property: "og:description", content: "إتمام تسجيل الدخول إلى منصة إداروم." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "robots", content: "noindex" },
    ],
  }),
  component: AuthCallback,
});

function AuthCallback() {
  const navigate = useNavigate();
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let done = false;
    const go = () => {
      if (done) return;
      done = true;
      navigate({ to: "/dashboard", replace: true });
    };
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      if (session) go();
    });
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) go();
    });
    const t = setTimeout(() => {
      if (!done) setFailed(true);
    }, 8000);
    return () => {
      sub.subscription.unsubscribe();
      clearTimeout(t);
    };
  }, [navigate]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4" dir="rtl">
      <div className="text-center">
        {failed ? (
          <>
            <p className="text-muted-foreground">تعذّر إتمام الدخول. حاول مرة أخرى.</p>
            <Link to="/login" className="mt-4 inline-block text-primary underline">
              العودة إلى صفحة الدخول
            </Link>
          </>
        ) : (
          <p className="text-muted-foreground">جارٍ إتمام تسجيل الدخول…</p>
        )}
      </div>
    </div>
  );
}
