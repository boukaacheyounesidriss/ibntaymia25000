import { createFileRoute, Link } from "@tanstack/react-router";
import { KeyRound, LifeBuoy, School, BookOpen, ShieldQuestion } from "lucide-react";
import { PublicHeader } from "@/components/PublicHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/support")({
  head: () => ({
    meta: [
      { title: "الدعم ومساعدة الحسابات — إداروم" },
      { name: "description", content: "استرجاع كلمة المرور ومشاكل الدخول وطلب المساعدة من إدارة ثانوية ابن تيمية." },
      { property: "og:title", content: "الدعم ومساعدة الحسابات — إداروم" },
      { property: "og:description", content: "حلول سريعة لنسيان كلمة المرور ومشاكل الدخول في منصة إداروم." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: SupportPage,
});

function SupportPage() {
  return (
    <div dir="rtl" className="min-h-screen bg-background">
      <PublicHeader />
      <main className="mx-auto max-w-2xl space-y-5 px-4 py-8">
        <div className="space-y-2 text-center">
          <LifeBuoy className="mx-auto h-10 w-10 text-primary" />
          <h1 className="font-display text-2xl font-bold">مركز الدعم</h1>
          <p className="text-sm text-muted-foreground">اختر مشكلتك وسنرشدك للحل.</p>
        </div>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2 text-lg"><KeyRound className="h-5 w-5" /> نسيت كلمة المرور</CardTitle></CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p>إن كان لديك بريد حقيقي مربوط بحسابك، استرجع كلمة المرور بنفسك:</p>
            <Button asChild className="w-full"><Link to="/forgot-password">استرجاع كلمة المرور</Link></Button>
            <p className="text-muted-foreground">إن كان حسابك ببريد أو اسم دخول افتراضي من الثانوية، فلن تصلك رسالة؛ توجّه إلى مكتب المراقب العام ليعيد تعيين كلمة المرور.</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2 text-lg"><ShieldQuestion className="h-5 w-5" /> لا أستطيع الدخول</CardTitle></CardHeader>
          <CardContent>
            <ul className="list-disc space-y-2 pe-5 text-sm">
              <li>تأكد من كتابة البريد كاملاً دون فراغات، وأن لغة لوحة المفاتيح صحيحة.</li>
              <li>إن ربطت حسابك بـ Google أو Apple استعمل الزر الخاص بهما.</li>
              <li>رمز PIN للأستاذ ليس كلمة مرور الدخول؛ هو للإمضاء فقط.</li>
            </ul>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2 text-lg"><School className="h-5 w-5" /> التواصل مع الإدارة</CardTitle></CardHeader>
          <CardContent className="text-sm">
            <p>مكتب المراقب العام بثانوية تقي الدين ابن تيمية — قسنطينة، خلال أوقات الدوام. أحضر بطاقة التلميذ أو بطاقة المهنة للتحقق من هويتك.</p>
          </CardContent>
        </Card>

        <Button asChild variant="outline" className="w-full gap-2">
          <Link to="/help"><BookOpen className="h-4 w-4" /> الأسئلة الشائعة وشروحات خطوة بخطوة</Link>
        </Button>
      </main>
    </div>
  );
}
