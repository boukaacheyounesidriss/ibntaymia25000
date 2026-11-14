import { Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { Download, Users, CalendarDays, Database, ShieldCheck, FileUp, Phone, UserCheck } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/lib/use-auth";
import { exportBackup } from "@/lib/backup.functions";

const controls = [
  { to: "/dashboard/users", label: "الحسابات وكلمات المرور", icon: Users },
  { to: "/dashboard/permissions", label: "الأدوار والصلاحيات", icon: ShieldCheck },
  { to: "/dashboard/schedule", label: "الأقسام والحصص", icon: CalendarDays },
  { to: "/dashboard/data", label: "سجلات المؤسسة", icon: Database },
  { to: "/dashboard/import", label: "الاستيراد الجماعي", icon: FileUp },
  { to: "/dashboard/parent-phones", label: "أرقام الأولياء", icon: Phone },
  { to: "/dashboard/class-reps", label: "مسؤولو الأقسام", icon: UserCheck },
] as const;

export function AdminControls() {
  const { roles } = useAuth();
  const backup = useServerFn(exportBackup);
  const [busy, setBusy] = useState(false);
  if (!roles.includes("admin") && !roles.includes("developer")) return null;
  async function download() {
    setBusy(true);
    try {
      const result = await backup();
      const url = URL.createObjectURL(new Blob([JSON.stringify(result)], { type: "application/json" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = `idarom-data-${new Date().toISOString().slice(0, 10)}.json`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast.success("نُزّلت نسخة بيانات المؤسسة");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "تعذر تنزيل البيانات");
    } finally { setBusy(false); }
  }
  return (
    <section className="space-y-4 border-b border-border pb-6" aria-labelledby="admin-controls-heading">
      <h2 id="admin-controls-heading" className="text-lg font-semibold">إدارة المؤسسة</h2>
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {controls.map(({ to, label, icon: Icon }) => (
          <Button key={to} asChild variant="outline" className="h-auto min-h-11 justify-start whitespace-normal text-start">
            <Link to={to}><Icon className="size-4 shrink-0" />{label}</Link>
          </Button>
        ))}
        <Button variant="outline" disabled={busy} onClick={download} className="h-auto min-h-11 justify-start whitespace-normal text-start">
          <Download className="size-4 shrink-0" />{busy ? "جارٍ تجهيز النسخة…" : "تنزيل نسخة بيانات المؤسسة"}
        </Button>
      </div>
    </section>
  );
}