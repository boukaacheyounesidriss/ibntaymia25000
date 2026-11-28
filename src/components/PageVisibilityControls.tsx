import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { NAV_ITEMS } from "@/lib/nav-config";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { friendlyError } from "@/lib/friendly-error";

type Props = { userId: string; roles: { key: string; label: string }[]; accounts: { id: string; full_name: string | null }[] };
export function PageVisibilityControls({ userId, roles, accounts }: Props) {
  const { t } = useTranslation();
  const qc = useQueryClient();
  const [kind, setKind] = useState("all");
  const [target, setTarget] = useState("");
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(false);
  const { data: rules = [], isPending, error } = useQuery({
    queryKey: ["owner-page-rules"],
    queryFn: async () => {
      const { data, error } = await supabase.from("page_visibility_rules").select("id,page,target_type,target,hidden").order("page").limit(1000);
      if (error) throw error;
      return data;
    },
  });
  async function change(page: string, mode: string) {
    if (kind !== "all" && !target) return;
    setBusy(true);
    try {
      if (mode === "inherit") {
        const { error } = await supabase.from("page_visibility_rules").delete().eq("page", page).eq("target_type", kind).eq("target", target);
        if (error) throw error;
      } else {
        const { error } = await supabase.from("page_visibility_rules").upsert({
          page, target_type: kind, target, hidden: mode === "hide", updated_by: userId, updated_at: new Date().toISOString(),
        }, { onConflict: "page,target_type,target" });
        if (error) throw error;
      }
      await Promise.all([qc.invalidateQueries({ queryKey: ["owner-page-rules"] }), qc.invalidateQueries({ queryKey: ["page-visibility"] })]);
      toast.success(t("pageRules.saved"));
    } catch (e) { toast.error(friendlyError(e)); } finally { setBusy(false); }
  }
  const choices = kind === "role" ? roles.map((r) => ({ id: r.key, name: r.label })) : accounts.map((a) => ({ id: a.id, name: a.full_name ?? a.id }));
  return <section className="space-y-4">
    <div className="grid gap-3 sm:grid-cols-2">
      <Select value={kind} onValueChange={(v) => { setKind(v); setTarget(""); }}><SelectTrigger aria-label={t("pageRules.audience")}><SelectValue /></SelectTrigger><SelectContent>
        <SelectItem value="all">{t("pageRules.all")}</SelectItem><SelectItem value="role">{t("pageRules.role")}</SelectItem><SelectItem value="user">{t("pageRules.user")}</SelectItem>
      </SelectContent></Select>
      {kind !== "all" && <Select value={target} onValueChange={setTarget}><SelectTrigger aria-label={t("pageRules.choose")}><SelectValue placeholder={t("pageRules.choose")} /></SelectTrigger><SelectContent>{choices.map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}</SelectContent></Select>}
    </div>
    <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder={t("pageRules.search")} />
    {isPending && <p>{t("pageRules.loading")}</p>}
    {error && <p className="text-destructive">{friendlyError(error)}</p>}
    <div className="divide-y divide-border">
      {NAV_ITEMS.filter((p) => p.url !== "/dashboard" && p.url !== "/dashboard/permissions" && t(p.labelKey).includes(search)).map((p) => {
        const rule = rules.find((r) => r.page === p.url && r.target_type === kind && r.target === target);
        return <div key={p.url} className="flex min-h-14 items-center justify-between gap-2 py-3">
          <span className="min-w-0 text-sm">{t(p.labelKey)}</span>
          <Select disabled={busy || isPending || !!error || (kind !== "all" && !target)} value={rule ? rule.hidden ? "hide" : "show" : "inherit"} onValueChange={(v) => void change(p.url, v)}>
            <SelectTrigger className="w-32 shrink-0" aria-label={t(p.labelKey)}><SelectValue /></SelectTrigger><SelectContent>
              <SelectItem value="inherit">{t("pageRules.inherit")}</SelectItem><SelectItem value="hide">{t("pageRules.hide")}</SelectItem><SelectItem value="show">{t("pageRules.show")}</SelectItem>
            </SelectContent></Select>
          </Select>
        </div>;
      })}
    </div>
    <Button variant="outline" onClick={() => void qc.invalidateQueries({ queryKey: ["owner-page-rules"] })}>{t("pageRules.refresh")}</Button>
  </section>;
}
