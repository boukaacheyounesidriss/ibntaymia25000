import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/use-auth";

/** Official name (student/teacher/staff record) of the signed-in user; never shows the email as a name. */
export function useDisplayName(): string {
  const { user } = useAuth();
  const { data } = useQuery({
    queryKey: ["my-display-name", user?.id],
    enabled: !!user,
    staleTime: 10 * 60 * 1000,
    queryFn: async () => {
      const { data } = await supabase.rpc("my_display_name");
      return (data as string | null) ?? null;
    },
  });
  const meta = user?.user_metadata?.["full_name"] as string | undefined;
  return data || (meta && !meta.includes("@") ? meta : "") || "مستخدم إداروم";
}
