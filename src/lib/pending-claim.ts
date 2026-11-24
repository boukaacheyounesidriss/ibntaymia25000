const KEY = "pending_claim_code";
export const CLAIM_CODE_RE = /^TAYM-[A-Z0-9]{4}-[A-Z0-9]{4}$/;
export function normalizeClaimCode(raw: string): string {
  const s = raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
  const body = s.startsWith("TAYM") ? s.slice(4) : s;
  return body.length === 8 ? `TAYM-${body.slice(0, 4)}-${body.slice(4)}` : raw.trim().toUpperCase();
}
export function setPendingClaim(code: string) { try { localStorage.setItem(KEY, code); } catch { /* ignore */ } }
export function getPendingClaim(): string | null { try { return localStorage.getItem(KEY); } catch { return null; } }
export function clearPendingClaim() { try { localStorage.removeItem(KEY); } catch { /* ignore */ } }
/** Where to go after sign-in: the claim page when a code is waiting, else the dashboard. */
export function afterLoginPath(): "/claim" | "/dashboard" { return getPendingClaim() ? "/claim" : "/dashboard"; }
