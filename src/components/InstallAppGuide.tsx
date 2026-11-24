import { useEffect, useState } from "react";
import { Share, PlusSquare, Copy, Smartphone } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

type Kind = "ios-safari" | "ios-other" | "android" | null;

/** Explains how to add the app to the home screen; iPhones can only install from Safari. */
export function InstallAppGuide() {
  const [kind, setKind] = useState<Kind>(null);
  useEffect(() => {
    const ua = navigator.userAgent;
    const standalone = window.matchMedia("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone;
    if (standalone) return;
    const ios = /iPhone|iPad|iPod/i.test(ua) || (ua.includes("Macintosh") && navigator.maxTouchPoints > 1);
    if (ios) setKind(/CriOS|FxiOS|EdgiOS|OPiOS|FBAN|FBAV|Instagram|Messenger/i.test(ua) ? "ios-other" : "ios-safari");
    else if (/Android/i.test(ua)) setKind("android");
  }, []);
  if (!kind) return null;
  const copy = async () => {
    try { await navigator.clipboard.writeText(window.location.origin); toast.success("نُسخ الرابط؛ الصقه في Safari"); }
    catch { toast.error("انسخ الرابط يدوياً: " + window.location.origin); }
  };
  return (
    <Card className="border-primary/30 bg-primary/5">
      <CardContent className="space-y-2 pt-4 text-sm" dir="rtl">
        <p className="flex items-center gap-2 font-semibold"><Smartphone className="h-4 w-4 text-primary" /> ثبّت التطبيق على هاتفك</p>
        {kind === "ios-other" && (<>
          <p>في الآيفون يتم التثبيت من متصفح <b>Safari</b> فقط. انسخ الرابط وافتحه في Safari.</p>
          <Button size="sm" variant="outline" onClick={copy}><Copy className="ms-1 h-4 w-4" /> نسخ الرابط</Button>
        </>)}
        {kind === "ios-safari" && (
          <ol className="list-decimal space-y-1 ps-5">
            <li className="flex-wrap">اضغط زر المشاركة <Share className="inline h-4 w-4" /> أسفل الشاشة.</li>
            <li>اختر «إضافة إلى الشاشة الرئيسية» <PlusSquare className="inline h-4 w-4" />.</li>
            <li>اضغط «إضافة»، وستجد أيقونة التطبيق على شاشتك.</li>
          </ol>
        )}
        {kind === "android" && <p>افتح قائمة المتصفح ⋮ ثم اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية».</p>}
      </CardContent>
    </Card>
  );
}
