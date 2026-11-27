import { useEffect, useState, type ReactNode } from "react";
import { useRouterState } from "@tanstack/react-router";
import { Wrench } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

type State = { enabled: boolean; message: string };
// Pages that must stay reachable so the owner can sign in during maintenance.
const OPEN_PATHS = ["/login", "/auth/callback", "/forgot-password", "/reset-password"];

export function MaintenanceGate({ children }: { children: ReactNode }) {
  const path = useRouterState({ select: (s) => s.location.pathname });
  const [state, setState] = useState<State | null>(null);
  const [isOwner, setIsOwner] = useState(false);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      const { data } = await supabase.from("site_maintenance").select("enabled,message").maybeSingle();
      const { data: s } = await supabase.auth.getSession();
      let owner = false;
      if (s.session) {
        const { data: o } = await supabase.rpc("is_role_owner");
        owner = o === true;
      }
      if (alive) {
        setState(data ? { enabled: data.enabled, message: data.message } : null);
        setIsOwner(owner);
      }
    };
    void load();
    const t = window.setInterval(load, 60_000);
    const { data: sub } = supabase.auth.onAuthStateChange((e) => {
      if (e === "SIGNED_IN" || e === "SIGNED_OUT") void load();
    });
    return () => {
      alive = false;
      window.clearInterval(t);
      sub.subscription.unsubscribe();
    };
  }, []);

  if (!state?.enabled || isOwner || OPEN_PATHS.includes(path)) {
    return (
      <>
        {state?.enabled && isOwner && (
          <div className="sticky top-0 z-50 bg-destructive px-3 py-1 text-center text-xs text-destructive-foreground">
            الموقع موقوف للجميع حالياً — أنت وحدك تراه
          </div>
        )}
        {children}
      </>
    );
  }
  return (
    <div dir="rtl" className="flex min-h-screen items-center justify-center bg-background p-6">
      <div className="max-w-md space-y-4 text-center">
        <Wrench className="mx-auto h-12 w-12 text-primary" />
        <h1 className="text-2xl font-bold">التطبيق متوقف مؤقتاً</h1>
        <p className="whitespace-pre-line text-muted-foreground">
          {state.message || "نعتذر، التطبيق في صيانة حالياً. يرجى المحاولة لاحقاً."}
        </p>
        <a href="/login" className="text-xs text-muted-foreground underline">دخول الإدارة</a>
      </div>
    </div>
  );
}
