import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Power, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";

const PRESETS = ["أعمال صيانة وترميم", "تحديث وتطوير التطبيق", "فترة الامتحانات", "أسباب إدارية"];

export function MaintenanceControl() {
  const qc = useQueryClient();
  const [owner, setOwner] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    void (async () => {
      const { data: o } = await supabase.rpc("is_role_owner");
      if (o !== true) return;
      setOwner(true);
      const { data } = await supabase.from("site_maintenance").select("enabled,message").maybeSingle();
      if (data) { setEnabled(data.enabled); setMessage(data.message); }
    })();
  }, []);

  if (!owner) return null;

  async function save(next: boolean) {
    setSaving(true);
    const { data: u } = await supabase.auth.getUser();
    const { error } = await supabase.from("site_maintenance")
      .update({ enabled: next, message, updated_at: new Date().toISOString(), updated_by: u.user?.id ?? null })
      .eq("id", true);
    setSaving(false);
    if (error) return toast.error("تعذر الحفظ", { description: error.message });
    setEnabled(next);
    toast.success(next ? "تم إيقاف التطبيق للجميع عداك" : "عاد التطبيق للعمل للجميع");
  }

  async function refreshAll() {
    await qc.cancelQueries();
    qc.clear();
    if ("caches" in window) {
      const keys = await caches.keys();
      await Promise.allSettled(keys.map((k) => caches.delete(k)));
    }
    await supabase.auth.refreshSession();
    toast.success("تم تفريغ الذاكرة المؤقتة وإعادة الاتصال");
    window.setTimeout(() => window.location.reload(), 600);
  }

  return (
    <Card className="border-destructive/40">
      <CardHeader><CardTitle className="flex items-center gap-2"><Power className="h-5 w-5" /> إيقاف التطبيق وإعادة التشغيل</CardTitle></CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between gap-3">
          <div>
            <div className="font-medium">إيقاف التطبيق عند الجميع</div>
            <p className="text-sm text-muted-foreground">يرى الجميع رسالتك، وتبقى أنت قادراً على استعماله كاملاً.</p>
          </div>
          <Switch checked={enabled} disabled={saving} onCheckedChange={(v) => void save(v)} aria-label="إيقاف التطبيق" />
        </div>
        <div className="flex flex-wrap gap-2">
          {PRESETS.map((p) => (
            <Button key={p} size="sm" variant="outline" onClick={() => setMessage(`تم إيقاف التطبيق مؤقتاً بسبب: ${p}.`)}>{p}</Button>
          ))}
        </div>
        <Textarea value={message} onChange={(e) => setMessage(e.target.value)} placeholder="السبب الذي يظهر للمستخدمين" rows={3} />
        <div className="flex flex-wrap gap-2">
          <Button disabled={saving} onClick={() => void save(enabled)}>حفظ الرسالة</Button>
          <Button variant="secondary" onClick={() => void refreshAll()}><RefreshCw className="ml-1 h-4 w-4" /> إنعاش التطبيق والاتصال</Button>
        </div>
      </CardContent>
    </Card>
  );
}
