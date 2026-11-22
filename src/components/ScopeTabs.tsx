import { SCOPE_LABEL, type Scope } from "@/lib/subgroups";

/** Quick switch between whole class / G1 / G2 / merged for one attendance session. */
export function ScopeTabs({ value, onChange, slotGroup }: { value: Scope; onChange: (s: Scope) => void; slotGroup: string }) {
  const options: Scope[] = slotGroup === "all" ? ["all", "g1", "g2"] : ["g1", "g2", "merged"];
  return (
    <div className="grid grid-cols-3 gap-1 rounded-xl border bg-muted/40 p-1" role="tablist" aria-label="الفوج">
      {options.map((o) => (
        <button key={o} type="button" role="tab" aria-selected={value === o} onClick={() => onChange(o)}
          className={`min-h-11 rounded-lg px-2 text-sm font-medium ${value === o ? "bg-primary text-primary-foreground" : "text-foreground"}`}>
          {SCOPE_LABEL[o]}
        </button>
      ))}
    </div>
  );
}
