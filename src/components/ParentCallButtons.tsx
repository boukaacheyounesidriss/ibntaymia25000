import { Phone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { normalizeDzPhone } from "@/lib/phone";

type P = { father_phone?: string | null; mother_phone?: string | null; guardian_phone?: string | null };

/** Opens the phone dialer with the parent's number ready; the user still decides to call. */
export function ParentCallButtons({ s, size = "sm" }: { s: P | null | undefined; size?: "sm" | "default" }) {
  if (!s) return null;
  const opts = [
    { label: "الأب", phone: s.father_phone },
    { label: "الأم", phone: s.mother_phone },
  ].filter((o) => o.phone);
  if (!opts.length && s.guardian_phone) opts.push({ label: "الولي", phone: s.guardian_phone });
  if (!opts.length) return null;
  return (
    <>
      {opts.map((o) => {
        const n = normalizeDzPhone(o.phone!) ?? o.phone!;
        return (
          <Button key={o.label} asChild size={size} variant="outline" className="gap-1">
            <a href={`tel:${n}`} aria-label={`اتصال ب${o.label}`}><Phone className="h-4 w-4" /> اتصال {o.label}</a>
          </Button>
        );
      })}
    </>
  );
}
