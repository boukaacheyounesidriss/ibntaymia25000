import { useQuery } from "@tanstack/react-query";
import { Download, FileText, RefreshCw } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { LESSON_BUCKET, fileSize, readAttachments } from "@/lib/lesson-files";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/lib/use-auth";

export function LessonAttachments({ value }: { value: unknown }) {
  const files = readAttachments(value);
  const { user } = useAuth();
  const { data, isPending, isError, refetch } = useQuery({
    queryKey: ["lesson-file-links", user?.id, files.map((f) => f.path)],
    enabled: files.length > 0 && !!user,
    staleTime: 4 * 60 * 1000,
    refetchInterval: 4 * 60 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase.storage.from(LESSON_BUCKET).createSignedUrls(files.map((f) => f.path), 600);
      if (error) throw error;
      if (data.some((f) => f.error)) throw new Error("تعذّر فتح بعض المرفقات");
      return data;
    },
  });
  if (!files.length) return null;
  return <div className="space-y-2 pt-2">
    {files.map((f, i) => {
      const url = data?.[i]?.signedUrl;
      return <div key={f.path} className="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-t border-border py-2">
        <div className="min-w-0"><p className="flex min-w-0 items-center gap-2"><FileText className="h-4 w-4 shrink-0 text-primary" /><span className="truncate" title={f.name}>{f.name}</span></p><p className="text-xs text-muted-foreground" dir="ltr">{fileSize(f.size)}</p></div>
        {url ? <Button asChild variant="outline" size="icon" aria-label={`فتح أو تنزيل ${f.name}`}><a href={url} target="_blank" rel="noopener noreferrer"><Download /></a></Button> : <Button disabled size="icon" variant="outline" aria-label="جارٍ تجهيز الملف"><Download /></Button>}
      </div>;
    })}
    {isPending && <p className="text-xs text-muted-foreground">جارٍ تجهيز المرفقات…</p>}
    {isError && <Button size="sm" variant="outline" onClick={() => refetch()}><RefreshCw /> إعادة فتح المرفقات</Button>}
  </div>;
}
