import { useQuery } from "@tanstack/react-query";
import { CalendarDays } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { WEEKDAYS } from "@/lib/teacher-hub";
import { SCOPE_LABEL, defaultScope } from "@/lib/subgroups";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

export function ChildWeeklySchedule({ classId, subgroup }: { classId: string; subgroup: string | null }) {
  const { data: slots = [], isPending, isError } = useQuery({
    queryKey: ["child-weekly-schedule", classId],
    queryFn: async () => {
      const { data, error } = await supabase.from("schedule_slots").select("id, weekday, start_time, end_time, subject, room, group_label").eq("class_id", classId).eq("is_active", true).order("start_time");
      if (error) throw error;
      return data ?? [];
    },
  });
  return <Card><CardHeader><CardTitle className="flex items-center gap-2 text-base"><CalendarDays /> جدول الابن الأسبوعي {subgroup && <Badge variant="outline">{SCOPE_LABEL[defaultScope(subgroup)]}</Badge>}</CardTitle></CardHeader>
    <CardContent className="space-y-4">
      {isPending && <p className="text-sm text-muted-foreground">جارٍ تحميل الجدول…</p>}
      {isError && <p className="text-sm text-destructive">تعذّر تحميل الجدول</p>}
      {!isPending && !isError && !slots.length && <p className="text-sm text-muted-foreground">لم يُضف جدول لهذا القسم بعد.</p>}
      {WEEKDAYS.map((day, weekday) => {
        const list = slots.filter((s) => s.weekday === weekday && (!subgroup || defaultScope(s.group_label) === "all" || s.group_label === subgroup));
        if (!list.length) return null;
        return <section key={day} className="min-w-0"><h3 className="mb-2 font-semibold text-primary">{day}</h3><div className="divide-y divide-border">{list.map((s) => <div key={s.id} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 py-2 text-sm"><div className="min-w-0"><p className="break-words font-medium">{s.subject}</p><p className="text-xs text-muted-foreground">{s.room ? `القاعة ${s.room} · ` : ""}{SCOPE_LABEL[defaultScope(s.group_label)]}</p></div><bdi className="shrink-0 text-xs tabular-nums">{s.start_time.slice(0, 5)}–{s.end_time.slice(0, 5)}</bdi></div>)}</div></section>;
      })}
    </CardContent>
  </Card>;
}
