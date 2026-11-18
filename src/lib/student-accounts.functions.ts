import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const input = z.object({
  studentId: z.string().uuid(),
  username: z.string().trim().toLowerCase().regex(/^[a-z0-9._-]{3,40}$/, "اسم المستخدم: حروف لاتينية وأرقام فقط"),
  password: z.string().min(8).max(72),
});

/** Management creates a login for an existing student record and links it. Grants only the student role. */
export const createLinkedStudentAccount = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((d: unknown) => input.parse(d))
  .handler(async ({ data, context }) => {
    const { data: ok } = await context.supabase.rpc("is_management", { _uid: context.userId });
    if (ok !== true) throw new Error("مرفوض: هذه العملية للإدارة فقط.");
    const { supabaseAdmin: db } = await import("@/integrations/supabase/client.server");
    const { data: st, error: sErr } = await db.from("students")
      .select("id, full_name, user_id, enrollment_status").eq("id", data.studentId).maybeSingle();
    if (sErr) throw new Error(sErr.message);
    if (!st) throw new Error("التلميذ غير موجود.");
    if (st.user_id) throw new Error("هذا التلميذ يملك حساباً مسبقاً.");
    if (st.enrollment_status !== "active") throw new Error("التلميذ غير متمدرس.");
    const email = `${data.username}@ibntaymia.school`;
    const { data: created, error } = await db.auth.admin.createUser({
      email, password: data.password, email_confirm: true, user_metadata: { full_name: st.full_name },
    });
    if (error) throw new Error(error.message.includes("already") ? "اسم المستخدم مستعمل، اختر غيره." : error.message);
    const uid = created.user.id;
    await db.from("profiles").upsert({ id: uid, full_name: st.full_name, preferred_language: "ar" });
    await db.from("user_roles").delete().eq("user_id", uid);
    const { error: rErr } = await db.from("user_roles").insert({ user_id: uid, role: "student" });
    if (rErr) throw new Error(rErr.message);
    const { error: lErr } = await db.from("students").update({ user_id: uid }).eq("id", st.id).is("user_id", null);
    if (lErr) throw new Error(lErr.message);
    return { userId: uid, username: data.username };
  });
