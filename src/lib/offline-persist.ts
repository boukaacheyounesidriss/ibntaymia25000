import type { QueryClient } from "@tanstack/react-query";
import { persistQueryClient } from "@tanstack/react-query-persist-client";
import { createSyncStoragePersister } from "@tanstack/query-sync-storage-persister";
import { flushAttendanceOutbox } from "@/lib/attendance-outbox";

/** Keeps the last-seen data on the device so pages open offline, and sends queued attendance once online. */
export function startOfflineSupport(queryClient: QueryClient): () => void {
  if (typeof window === "undefined") return () => {};
  let unsub: () => void = () => {};
  try {
    const persister = createSyncStoragePersister({ storage: window.localStorage, key: "idaroom-cache", throttleTime: 2000 });
    [unsub] = persistQueryClient({ queryClient: queryClient as never, persister, maxAge: 24 * 60 * 60 * 1000, buster: "v1" });
  } catch {
    /* storage unavailable (private mode) — app still works online */
  }
  const flush = () => { void flushAttendanceOutbox().then((n) => { if (n > 0) void queryClient.invalidateQueries(); }); };
  window.addEventListener("online", flush);
  const timer = window.setInterval(flush, 60_000);
  flush();
  return () => { unsub(); window.removeEventListener("online", flush); window.clearInterval(timer); };
}
