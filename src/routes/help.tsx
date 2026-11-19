import { createFileRoute, Link } from "@tanstack/react-router";
import { BookOpen } from "lucide-react";
import { PublicHeader } from "@/components/PublicHeader";
import { HelpGuides } from "@/components/HelpGuides";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/help")({
  head: () => ({
    meta: [
      { title: "الأسئلة الشائعة وطريقة الاستعمال — إداروم" },
      { name: "description", content: "شروحات مبسطة خطوة بخطوة لاستعمال منصة إداروم: كلمة المرور، PIN، الحضور ورسائل الغياب." },
      { property: "og:title", content: "الأسئلة الشائعة — إداروم" },
      { property: "og:description", content: "حلول مبسطة خطوة بخطوة لأكثر الأسئلة شيوعاً في إداروم." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: HelpPage,
});

function HelpPage() {
  return (
    <div dir="rtl" className="min-h-screen bg-background">
      <PublicHeader />
      <main className="mx-auto max-w-2xl space-y-5 px-4 py-8">
        <div className="space-y-2 text-center">
          <BookOpen className="mx-auto h-10 w-10 text-primary" />
          <h1 className="font-display text-2xl font-bold">الأسئلة الشائعة</h1>
          <p className="text-sm text-muted-foreground">اضغط على السؤال لترى الحل خطوة بخطوة.</p>
        </div>
        <HelpGuides />
        <Button asChild variant="outline" className="w-full"><Link to="/support">لم تجد الحل؟ مركز الدعم</Link></Button>
      </main>
    </div>
  );
}
