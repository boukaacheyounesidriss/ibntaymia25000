import { useQuery } from "@tanstack/react-query";
import { CalendarX } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

const DECISION: Record<string, string> = { substitute: "أستاذ مستخلف", study_room: "قاعة المراجعة", dismissed: "تسريح القسم" };
const iso = (d: Date) => d.toISOString().slice(0, 10);

/** Upcoming slots cancelled by a declared teacher absence, for the viewer's own class(es). */
export function CancelledSlotsNotice() {
  const from = iso(new Date());
  const to = iso(new Date(Date.now() + 6 * 864e5));
  const { data = [] } = useQuery({
    queryKey: ["cancelled-slots", from],
    queryFn: async () => {
      const { data: rows, error } = await supabase.rpc("my_cancelled_slots", { _from: from, _to: to });
      if (error || !rows?.length) return [];
      const ids = [...new Set(rows.map((r) => r.slot_id))];
      const { data: slots } = await supabase.from("schedule_slots").select("id, subject, start_time, end_time, classes(name)").in("id", ids);
      const m = new Map((slots ?? []).map((s) => [s.id, s]));
      return rows.map((r) => ({ ...r, slot: m.get(r.slot_id) })).sort((a, b) => (a.on_date + (a.slot?.start_time ?? "")).localeCompare(b.on_date + (b.slot?.start_time ?? "")));
    },
  });
  if (!data.length) return null;
  return (
    <Card className="border-destructive/40">
      <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><CalendarX className="h-4 w-4 text-destructive" /> حصص ملغاة لغياب الأستاذ</CardTitle></CardHeader>
      <CardContent className="space-y-2">
        {data.map((r) => (
          <div key={r.slot_id + r.on_date} className="flex flex-wrap items-center gap-2 rounded-md bg-muted/50 px-3 py-2 text-sm">
            <Badge variant="outline">{r.on_date === from ? "اليوم" : r.on_date}</Badge>
            <span className="font-mono text-xs">{r.slot?.start_time.slice(0, 5)}–{r.slot?.end_time.slice(0, 5)}</span>
            <span className="font-medium">{r.slot?.subject}</span>
            <span className="text-muted-foreground">{(r.slot?.classes as { name: string } | null)?.name}</span>
            <Badge variant={r.decision ? "secondary" : "destructive"}>{r.decision ? DECISION[r.decision] ?? r.decision : "في انتظار قرار الإدارة"}</Badge>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
