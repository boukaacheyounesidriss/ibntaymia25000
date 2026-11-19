import { createFileRoute, Link } from "@tanstack/react-router";
import { PageHeader } from "@/components/PageHeader";
import { HelpGuides } from "@/components/HelpGuides";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/dashboard/help")({
  head: () => ({
    meta: [
      { title: "المساعدة — إداروم" },
      { name: "description", content: "أسئلة شائعة وشروحات استعمال إداروم داخل حسابك." },
      { property: "og:title", content: "المساعدة — إداروم" },
      { property: "og:description", content: "أسئلة شائعة وشروحات استعمال إداروم خطوة بخطوة." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: DashboardHelp,
});

function DashboardHelp() {
  return (
    <div className="space-y-5">
      <PageHeader title="المساعدة والأسئلة الشائعة" description="حلول بسيطة خطوة بخطوة." />
      <div className="grid gap-2 sm:grid-cols-2">
        <Button asChild><Link to="/dashboard/profile">الأمان وكلمة المرور</Link></Button>
        <Button asChild variant="outline"><Link to="/support">مركز الدعم</Link></Button>
      </div>
      <HelpGuides />
    </div>
  );
}
