import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";
import { friendlyError } from "@/lib/friendly-error";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";

const today = () => new Date().toISOString().slice(0, 10);

/** Lets a teacher declare an absence (whole day or chosen periods); management is notified by the database. */
export function TeacherAbsenceCard() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const [date, setDate] = useState(today());
  const [reason, setReason] = useState("");
  const [picked, setPicked] = useState<string[]>([]);
  const weekday = new Date(date + "T12:00:00").getDay();

  const { data: slots = [] } = useQuery({
    queryKey: ["my-day-slots", user?.id, weekday],
    enabled: !!user,
    queryFn: async () => {
      const { data } = await supabase.from("schedule_slots").select("id, subject, start_time, end_time, classes(name)")
        .eq("teacher_id", user!.id).eq("weekday", weekday).eq("is_active", true).order("start_time");
      return data ?? [];
    },
  });
  const { data: mine = [] } = useQuery({
    queryKey: ["my-absences", user?.id],
    enabled: !!user,
    queryFn: async () => {
      const { data } = await supabase.from("teacher_absences").select("*").eq("teacher_id", user!.id).gte("absence_date", today()).order("absence_date");
      return data ?? [];
    },
  });

  const submit = async (whole: boolean) => {
    if (!user) return;
    if (!whole && picked.length === 0) return toast.error("اختر الحصص المعنية");
    if (!reason.trim()) return toast.error("اكتب سبب الغياب");
    const { error } = await supabase.from("teacher_absences").insert({
      teacher_id: user.id, absence_date: date, reason: reason.trim(), slot_ids: whole ? null : picked, created_by: user.id,
    });
    if (error) return toast.error(friendlyError(error));
    toast.success("أُرسل التصريح إلى الإدارة، وأُلغيت الحصص للتلاميذ");
    setPicked([]); setReason("");
    qc.invalidateQueries({ queryKey: ["my-absences"] });
  };
  const cancel = async (id: string) => {
    const { error } = await supabase.from("teacher_absences").delete().eq("id", id);
    if (error) return toast.error(friendlyError(error));
    toast.success("أُلغي التصريح");
    qc.invalidateQueries({ queryKey: ["my-absences"] });
  };
  const label = (ids: string[] | null) => (ids ? `${ids.length} حصة` : "اليوم كاملاً");

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader><CardTitle className="text-base">التصريح بغياب</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-sm">اليوم<Input type="date" min={today()} value={date} onChange={(e) => { setDate(e.target.value); setPicked([]); }} /></label>
            <label className="text-sm">السبب<Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="عطلة مرضية، ظرف عائلي..." /></label>
          </div>
          {slots.length === 0 ? <p className="text-sm text-muted-foreground">لا حصص لك في هذا اليوم.</p> : (
            <div className="grid gap-2">
              {slots.map((s) => (
                <label key={s.id} className="flex min-h-11 items-center gap-3 rounded-md border px-3 text-sm">
                  <input type="checkbox" className="h-5 w-5" checked={picked.includes(s.id)}
                    onChange={(e) => setPicked((p) => e.target.checked ? [...p, s.id] : p.filter((x) => x !== s.id))} />
                  <span className="font-mono text-xs">{s.start_time.slice(0, 5)}–{s.end_time.slice(0, 5)}</span>
                  <span className="font-medium">{(s.classes as { name: string } | null)?.name}</span>
                  <span className="text-muted-foreground">{s.subject}</span>
                </label>
              ))}
            </div>
          )}
          <div className="flex flex-wrap gap-2">
            <Button onClick={() => submit(false)} disabled={slots.length === 0}>غياب عن الحصص المحددة</Button>
            <Button variant="outline" onClick={() => submit(true)}>غياب اليوم كاملاً</Button>
          </div>
          <p className="text-xs text-muted-foreground">تصل الإدارة إشعاراً فوراً، وتظهر الحصص ملغاة للتلاميذ والأولياء، ولا يمكن تسجيل حضورها إلا عند الاستخلاف.</p>
        </CardContent>
      </Card>
      {mine.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">تصاريحي القادمة</CardTitle></CardHeader>
          <CardContent className="space-y-2">
            {mine.map((a) => (
              <div key={a.id} className="flex flex-wrap items-center gap-2 text-sm">
                <Badge variant="outline">{a.absence_date}</Badge><Badge variant="secondary">{label(a.slot_ids)}</Badge>
                <span className="text-muted-foreground">{a.reason}</span>
                <Button size="sm" variant="ghost" className="text-destructive" onClick={() => cancel(a.id)}>إلغاء</Button>
              </div>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
