import { useState, type FormEvent } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Lock } from "lucide-react";

import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function pinProblem(pin: string): string | null {
  if (!/^[0-9]{4,6}$/.test(pin)) return "الرمز من 4 إلى 6 أرقام";
  if (/^(\d)\1+$/.test(pin) || ["1234", "12345", "123456", "4321", "54321", "654321", "0123"].includes(pin))
    return "اختر رمزاً أقل سهولة";
  return null;
}

function cleanError(msg: string) {
  return msg.replace(/^[A-Z_]+:\s*/, "");
}

export function TeacherPinCard() {
  const qc = useQueryClient();
  const [pin, setPin] = useState("");
  const [confirm, setConfirm] = useState("");
  const [saving, setSaving] = useState(false);
  const { data: hasPin } = useQuery({
    queryKey: ["has-attendance-pin"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("has_my_attendance_pin");
      if (error) throw error;
      return !!data;
    },
  });

  async function submit(e: FormEvent) {
    e.preventDefault();
    const p = pinProblem(pin);
    if (p) return toast.error(p);
    if (pin !== confirm) return toast.error("الرمزان غير متطابقين");
    setSaving(true);
    const { error } = await supabase.rpc("set_my_attendance_pin", { _pin: pin });
    setSaving(false);
    if (error) return toast.error(cleanError(error.message));
    setPin("");
    setConfirm("");
    toast.success("تم حفظ رمز الإمضاء");
    qc.invalidateQueries({ queryKey: ["has-attendance-pin"] });
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 font-display">
          <Lock className="h-5 w-5" />
          رمز PIN السريع لإمضاء الحضور
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <p className="text-sm text-muted-foreground">
          {hasPin
            ? "لديك رمز مفعّل. يمكنك تغييره هنا. عند النسيان يعيد المدير تعيينه."
            : "لم تنشئ رمزاً بعد. أنشئه لتتمكن من إمضاء الحضور على جهاز مسؤول القسم."}
        </p>
        <form onSubmit={submit} className="grid gap-3 sm:grid-cols-3 sm:items-end">
          <div className="space-y-1">
            <Label htmlFor="pin">الرمز الجديد</Label>
            <Input id="pin" type="password" inputMode="numeric" maxLength={6} dir="ltr" autoComplete="new-password"
              value={pin} onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="pin2">تأكيد الرمز</Label>
            <Input id="pin2" type="password" inputMode="numeric" maxLength={6} dir="ltr" autoComplete="new-password"
              value={confirm} onChange={(e) => setConfirm(e.target.value.replace(/\D/g, ""))} />
          </div>
          <Button type="submit" disabled={saving}>{saving ? "جارٍ الحفظ..." : hasPin ? "تغيير الرمز" : "إنشاء الرمز"}</Button>
        </form>
      </CardContent>
    </Card>
  );
}
