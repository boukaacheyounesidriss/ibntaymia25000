import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { isRoleOwnerIdentity } from "@/lib/role-owner";
import { pageIsHidden, type VisibilityRule } from "@/lib/page-visibility-policy";

export function usePageVisibility(userId: string | undefined, roles: string[]) {
  const { data, isPending } = useQuery({
    queryKey: ["page-visibility", userId],
    enabled: !!userId,
    refetchInterval: 60_000,
    refetchOnWindowFocus: "always",
    queryFn: async () => {
      if (!userId) return { rules: [] as VisibilityRule[], customRoles: [] as string[] };
      const [rules, custom] = await Promise.all([
        supabase.from("page_visibility_rules").select("page,target_type,target,hidden").order("page").limit(1000),
        supabase.from("custom_user_roles").select("role_key").eq("user_id", userId).limit(100),
      ]);
      if (rules.error) throw rules.error;
      if (custom.error) throw custom.error;
      return { rules: rules.data, customRoles: custom.data.map((r) => r.role_key) };
    },
  });
  return {
    loading: !!userId && isPending,
    isHidden: (page: string) => !!userId && pageIsHidden(page, data?.rules ?? [], userId, [...roles, ...(data?.customRoles ?? [])], isRoleOwnerIdentity(userId)),
  };
}
