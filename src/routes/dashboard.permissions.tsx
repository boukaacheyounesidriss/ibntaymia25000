import { createFileRoute, redirect } from "@tanstack/react-router";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { Plus, Save, ShieldCheck, Loader2 } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { supabase } from "@/integrations/supabase/client";
import { useAuth, type AppRole } from "@/lib/use-auth";
import { PERMISSION_GROUPS, LIMIT_SETTINGS } from "@/lib/permissions";
import { friendlyError } from "@/lib/friendly-error";
import { isRoleOwnerIdentity } from "@/lib/role-owner";

export const Route = createFileRoute("/dashboard/permissions")({
  ssr: false,
  beforeLoad: async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw redirect({ to: "/login" });
    const { data, error } = await supabase.rpc("is_role_owner");
    if (error || data !== true) throw redirect({ to: "/dashboard" });
  },
  head: () => ({ meta: [
    { title: "إدارة الأدوار الحصرية — إداروم" },
    { name: "description", content: "إدارة الأدوار وصلاحيات الأدوار والحسابات لصاحب المؤسسة." },
    { property: "og:title", content: "إدارة الأدوار الحصرية — إداروم" },
    { property: "og:description", content: "إدارة الأدوار وصلاحيات الأدوار والحسابات لصاحب المؤسسة." },
    { property: "og:type", content: "website" }, { name: "twitter:card", content: "summary" },
  ] }),
  component: PermissionsPage,
});

type RoleDef = { key: string; label: string; description: string; builtin: boolean };
type Account = { id: string; full_name: string | null };
function PermissionsPage() {
  const { user } = useAuth();
  const [roles, setRoles] = useState<RoleDef[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [selectedRole, setSelectedRole] = useState("");
  const [selectedUser, setSelectedUser] = useState("");
  const [search, setSearch] = useState("");
  const [roleMap, setRoleMap] = useState<Record<string, boolean>>({});
  const [overrides, setOverrides] = useState<Record<string, boolean>>({});
  const [assigned, setAssigned] = useState<string[]>([]);
  const [label, setLabel] = useState("");
  const [description, setDescription] = useState("");
  const [newKey, setNewKey] = useState("");
  const [newLabel, setNewLabel] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [detailLoading, setDetailLoading] = useState(false);
  const [limits, setLimits] = useState<Record<string, string>>({});
  const role = roles.find(r => r.key === selectedRole);

  const load = useCallback(async () => {
    const results = await Promise.all([
      supabase.from("role_definitions").select("key,label,description,builtin").order("builtin", { ascending: false }).order("label"),
      supabase.from("profiles").select("id,full_name").order("full_name"),
      supabase.from("access_settings").select("key,value"),
    ]);
    for (const r of results) if (r.error) throw r.error;
    setRoles(results[0].data ?? []);
    setAccounts(results[1].data ?? []);
    setLimits(Object.fromEntries((results[2].data ?? []).map(r => [r.key, String(r.value)])));
    setSelectedRole(current => current || results[0].data?.[0]?.key || "");
  }, []);

  useEffect(() => { load().catch(e => toast.error(friendlyError(e))).finally(() => setLoading(false)); }, [load]);
  useEffect(() => {
    if (!role) return;
    let active = true;
    setLabel(role.label); setDescription(role.description); setDetailLoading(true); setRoleMap({});
    const query = role.builtin
      ? supabase.from("role_permissions").select("permission,allowed").eq("role", role.key as AppRole)
      : supabase.from("custom_role_permissions").select("permission,allowed").eq("role_key", role.key);
    query.then(({ data, error }) => {
      if (!active) return;
      if (error) toast.error(friendlyError(error));
      setRoleMap(Object.fromEntries((data ?? []).map(r => [r.permission, r.allowed]))); setDetailLoading(false);
    });
    return () => { active = false; };
  }, [role]);
  useEffect(() => {
    if (!selectedUser) return;
    let active = true;
    setDetailLoading(true); setOverrides({}); setAssigned([]);
    Promise.all([
      supabase.from("user_permission_overrides").select("permission,allowed").eq("user_id", selectedUser),
      supabase.from("custom_user_roles").select("role_key").eq("user_id", selectedUser),
      supabase.from("user_roles").select("role").eq("user_id", selectedUser),
    ]).then(results => {
      if (!active) return;
      for (const r of results) if (r.error) toast.error(friendlyError(r.error));
      setOverrides(Object.fromEntries((results[0].data ?? []).map(r => [r.permission, r.allowed])));
      setAssigned([...(results[1].data ?? []).map(r => r.role_key), ...(results[2].data ?? []).map(r => r.role)]);
      setDetailLoading(false);
    });
    return () => { active = false; };
  }, [selectedUser]);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    try { await action(); toast.success("تم الحفظ"); } catch (e) { toast.error(friendlyError(e)); } finally { setBusy(false); }
  }
  function checked(result: { error: { message: string } | null }) { if (result.error) throw result.error; }
  async function saveRolePermission(permission: string, allowed: boolean) {
    if (!role) return;
    await run(async () => {
      if (role.builtin) checked(await supabase.from("role_permissions").upsert({ role: role.key as AppRole, permission, allowed, updated_by: user?.id }));
      else checked(await supabase.from("custom_role_permissions").upsert({ role_key: role.key, permission, allowed }));
      setRoleMap(m => ({ ...m, [permission]: allowed }));
    });
  }
  async function saveOverride(permission: string, mode: string) {
    await run(async () => {
      if (mode === "inherit") checked(await supabase.from("user_permission_overrides").delete().eq("user_id", selectedUser).eq("permission", permission));
      else checked(await supabase.from("user_permission_overrides").upsert({ user_id: selectedUser, permission, allowed: mode === "allow", updated_by: user?.id }));
      setOverrides(m => { const next = { ...m }; if (mode === "inherit") delete next[permission]; else next[permission] = mode === "allow"; return next; });
    });
  }
  async function assignRole(r: RoleDef, enabled: boolean) {
    const next = enabled ? [...assigned, r.key] : assigned.filter(key => key !== r.key);
    await run(async () => {
      if (r.builtin) checked(await supabase.rpc("owner_set_account_roles", { _user_id: selectedUser, _roles: next.filter(key => roles.some(d => d.key === key && d.builtin)) as AppRole[] }));
      else if (enabled) checked(await supabase.from("custom_user_roles").insert({ user_id: selectedUser, role_key: r.key }));
      else checked(await supabase.from("custom_user_roles").delete().eq("user_id", selectedUser).eq("role_key", r.key));
      setAssigned(next);
    });
  }
  if (loading) return <Loader2 className="size-6 animate-spin" aria-label="جارٍ التحميل" />;
  const disabled = busy || detailLoading;
  return <div className="mx-auto max-w-5xl space-y-6" dir="rtl">
    <PageHeader title="الأدوار والصلاحيات" />
    <div className="flex items-center gap-2 text-sm text-muted-foreground"><ShieldCheck className="size-4" />صاحب المؤسسة · {roles.filter(r => r.builtin).length} أدوار أساسية · {roles.filter(r => !r.builtin).length} أدوار مخصصة</div>
    <Tabs defaultValue="roles">
      <TabsList className="w-full"><TabsTrigger value="roles" className="flex-1">الأدوار</TabsTrigger><TabsTrigger value="accounts" className="flex-1">الحسابات</TabsTrigger><TabsTrigger value="limits" className="flex-1">الحدود</TabsTrigger></TabsList>
      <TabsContent value="roles" className="space-y-6 pt-4">
        <section className="space-y-3 border-b border-border pb-6">
          <h2 className="font-semibold">دور جديد</h2>
          <div className="grid gap-3 sm:grid-cols-[1fr_1fr_auto]">
            <div className="space-y-2"><Label htmlFor="role-label">اسم الدور</Label><Input id="role-label" value={newLabel} onChange={e => setNewLabel(e.target.value)} maxLength={120} /></div>
            <div className="space-y-2"><Label htmlFor="role-key">رمز الدور</Label><Input id="role-key" dir="ltr" placeholder="school_club" value={newKey} onChange={e => setNewKey(e.target.value)} maxLength={64} /></div>
            <Button className="self-end" disabled={busy || newLabel.trim().length < 2 || !/^[a-z][a-z0-9_]{1,63}$/.test(newKey)} onClick={() => run(async () => {
              checked(await supabase.from("role_definitions").insert({ key: newKey, label: newLabel.trim() })); await load(); setSelectedRole(newKey); setNewKey(""); setNewLabel("");
            })}><Plus className="size-4" />إنشاء الدور</Button>
          </div>
        </section>
        <Select value={selectedRole} onValueChange={setSelectedRole}><SelectTrigger aria-label="اختيار الدور"><SelectValue /></SelectTrigger><SelectContent>{roles.map(r => <SelectItem key={r.key} value={r.key}>{r.label} · {r.builtin ? "أساسي" : "مخصص"}</SelectItem>)}</SelectContent></Select>
        {role && <><div className="grid gap-3 sm:grid-cols-2"><div className="space-y-2"><Label htmlFor="edit-role">اسم الدور</Label><Input id="edit-role" value={label} onChange={e => setLabel(e.target.value)} /></div><div className="space-y-2"><Label htmlFor="role-description">المهام</Label><Textarea id="role-description" value={description} onChange={e => setDescription(e.target.value)} maxLength={2000} /></div></div>
          <Button disabled={disabled || label.trim().length < 2} onClick={() => run(async () => { checked(await supabase.from("role_definitions").update({ label: label.trim(), description }).eq("key", role.key)); await load(); })}><Save className="size-4" />حفظ الدور</Button>
          <PermissionFields map={roleMap} disabled={disabled} toggle={saveRolePermission} />
        </>}
      </TabsContent>
      <TabsContent value="accounts" className="space-y-5 pt-4">
        <Input aria-label="بحث عن حساب" placeholder="بحث باسم صاحب الحساب" value={search} onChange={e => setSearch(e.target.value)} />
        <Select value={selectedUser} onValueChange={setSelectedUser}><SelectTrigger aria-label="اختيار الحساب"><SelectValue placeholder="اختر الحساب" /></SelectTrigger><SelectContent>{accounts.filter(a => (a.full_name ?? a.id).includes(search)).map(a => <SelectItem key={a.id} value={a.id}>{a.full_name ?? a.id}</SelectItem>)}</SelectContent></Select>
        {selectedUser && <>
          <section className="space-y-3 border-b border-border pb-5"><h2 className="font-semibold">الأدوار المسندة</h2><div className="grid gap-3 sm:grid-cols-2">{roles.map(r => <label key={r.key} className="flex items-center gap-3"><Checkbox checked={assigned.includes(r.key)} disabled={disabled || isRoleOwnerIdentity(selectedUser)} onCheckedChange={v => assignRole(r, v === true)} />{r.label}</label>)}</div></section>
          <PermissionFields map={overrides} disabled={disabled || isRoleOwnerIdentity(selectedUser)} mode onMode={saveOverride} />
        </>}
      </TabsContent>
      <TabsContent value="limits" className="space-y-5 pt-4">{LIMIT_SETTINGS.map(s => <div key={s.key} className="flex flex-wrap items-end gap-3"><div className="flex-1 space-y-1"><Label htmlFor={s.key}>{s.label}</Label><p className="text-xs text-muted-foreground">{s.hint}</p></div><Input id={s.key} className="w-24" type="number" min={0} value={limits[s.key] ?? ""} onChange={e => setLimits(m => ({ ...m, [s.key]: e.target.value }))} /><Button disabled={busy} onClick={() => run(async () => { const value = Number(limits[s.key]); if (!Number.isInteger(value) || value < 0) throw new Error("أدخل عدداً صحيحاً غير سالب"); checked(await supabase.from("access_settings").upsert({ key: s.key, value, updated_by: user?.id })); })}><Save className="size-4" />حفظ</Button></div>)}</TabsContent>
    </Tabs>
  </div>;
}

function PermissionFields({ map, disabled, toggle, mode, onMode }: { map: Record<string, boolean>; disabled: boolean; toggle?: (key: string, allowed: boolean) => void; mode?: boolean; onMode?: (key: string, mode: string) => void }) {
  return <div className="space-y-6">{PERMISSION_GROUPS.map(g => <section key={g.title} className="space-y-2"><h3 className="font-semibold">{g.title}</h3>{g.items.map(p => <div key={p.key} className="flex items-center justify-between gap-3 border-b border-border py-3"><div className="min-w-0 text-sm"><span>{p.label}</span>{p.hint && <p className="text-xs text-muted-foreground">{p.hint}</p>}</div>{mode ? <Select disabled={disabled} value={p.key in map ? map[p.key] ? "allow" : "deny" : "inherit"} onValueChange={v => onMode?.(p.key, v)}><SelectTrigger className="w-32 shrink-0" aria-label={p.label}><SelectValue /></SelectTrigger><SelectContent><SelectItem value="inherit">حسب الدور</SelectItem><SelectItem value="allow">مسموح</SelectItem><SelectItem value="deny">ممنوع</SelectItem></SelectContent></Select> : <Switch disabled={disabled} aria-label={p.label} checked={map[p.key] ?? false} onCheckedChange={v => toggle?.(p.key, v)} />}</div>)}</section>)}</div>;
}
