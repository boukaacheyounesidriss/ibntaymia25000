ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS teacher_edit_count integer NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.enforce_record_permissions()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE uid uuid := auth.uid(); win numeric; s_created timestamptz;
BEGIN
  IF TG_OP = 'INSERT' AND current_setting('app.kiosk_signed', true) = '1' THEN RETURN NEW; END IF;
  IF uid IS NULL OR is_management(uid) THEN RETURN COALESCE(NEW, OLD); END IF;
  IF TG_OP = 'INSERT' THEN
    IF NOT has_permission(uid,'attendance.take') THEN
      RAISE EXCEPTION 'PERM_DENIED: غير مسموح لك بتسجيل الحضور' USING ERRCODE='42501'; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP='UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.note IS NOT DISTINCT FROM OLD.note THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('app.teacher_edit', true),'') <> '1' THEN
    RAISE EXCEPTION 'PERM_DENIED: عدّل الحضور من شاشة «حضور حصتي ← حصص سجلتها»' USING ERRCODE='42501'; END IF;
  IF NOT has_permission(uid,'attendance.edit_after_save') THEN
    RAISE EXCEPTION 'PERM_DENIED: تعديل الحضور بعد الحفظ غير مسموح لحسابك' USING ERRCODE='42501'; END IF;
  IF TG_OP='UPDATE' AND OLD.status='late' AND NEW.status<>'late' AND NOT has_permission(uid,'attendance.override_late') THEN
    RAISE EXCEPTION 'PERM_DENIED: تغيير حالة "متأخر" غير مسموح لحسابك' USING ERRCODE='42501'; END IF;
  SELECT value INTO win FROM access_settings WHERE key='attendance_edit_window_hours';
  SELECT created_at INTO s_created FROM attendance_sessions WHERE id = OLD.session_id;
  IF win IS NOT NULL AND win > 0 AND s_created < now() - make_interval(hours => win::int) THEN
    RAISE EXCEPTION 'PERM_DENIED: انتهت المدة المسموحة للتعديل (% ساعة)', win::int USING ERRCODE='42501'; END IF;
  RETURN COALESCE(NEW, OLD);
END $function$;

CREATE OR REPLACE FUNCTION public.teacher_edit_attendance(_session uuid, _changes jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE uid uuid := auth.uid(); s record; mx int; mgmt boolean; c jsonb; n int := 0;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT * INTO s FROM attendance_sessions WHERE id = _session FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'جلسة غير موجودة'; END IF;
  mgmt := is_management(uid);
  IF NOT mgmt AND s.teacher_id <> uid THEN
    RAISE EXCEPTION 'PERM_DENIED: هذه الحصة ليست من تسجيلك' USING ERRCODE='42501'; END IF;
  SELECT COALESCE((SELECT value::int FROM access_settings WHERE key='attendance_teacher_max_edits'), 1) INTO mx;
  IF NOT mgmt AND s.teacher_edit_count >= mx THEN
    RAISE EXCEPTION 'PERM_DENIED: استنفدت عدد مرات التعديل المسموحة (%)', mx USING ERRCODE='42501'; END IF;
  PERFORM set_config('app.teacher_edit', '1', true);
  FOR c IN SELECT * FROM jsonb_array_elements(COALESCE(_changes,'[]'::jsonb)) LOOP
    IF (c->>'status') NOT IN ('present','absent','late') THEN RAISE EXCEPTION 'حالة غير صالحة'; END IF;
    UPDATE attendance_records SET status = c->>'status', updated_at = now()
      WHERE session_id = _session AND student_id = (c->>'student_id')::uuid AND status IS DISTINCT FROM c->>'status';
    IF FOUND THEN n := n + 1; END IF;
  END LOOP;
  PERFORM set_config('app.teacher_edit', '', true);
  IF n > 0 AND NOT mgmt THEN
    UPDATE attendance_sessions SET teacher_edit_count = teacher_edit_count + 1 WHERE id = _session;
  END IF;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.teacher_edit_attendance(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.teacher_edit_attendance(uuid, jsonb) TO authenticated;

CREATE TABLE public.page_visibility_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page text NOT NULL,
  target_type text NOT NULL CHECK (target_type IN ('all','role','user')),
  target text NOT NULL DEFAULT '',
  hidden boolean NOT NULL DEFAULT true,
  updated_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (page, target_type, target)
);
GRANT SELECT ON public.page_visibility_rules TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.page_visibility_rules TO authenticated;
GRANT ALL ON public.page_visibility_rules TO service_role;
ALTER TABLE public.page_visibility_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY pvr_read ON public.page_visibility_rules FOR SELECT TO authenticated USING (
  public.is_role_owner()
  OR target_type = 'all'
  OR (target_type = 'user' AND target = auth.uid()::text)
  OR (target_type = 'role' AND (
        EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = auth.uid() AND ur.role::text = target)
     OR EXISTS (SELECT 1 FROM public.custom_user_roles cr WHERE cr.user_id = auth.uid() AND cr.role_key = target)))
);
CREATE POLICY pvr_owner_ins ON public.page_visibility_rules FOR INSERT TO authenticated WITH CHECK (public.is_role_owner());
CREATE POLICY pvr_owner_upd ON public.page_visibility_rules FOR UPDATE TO authenticated USING (public.is_role_owner()) WITH CHECK (public.is_role_owner());
CREATE POLICY pvr_owner_del ON public.page_visibility_rules FOR DELETE TO authenticated USING (public.is_role_owner());

CREATE OR REPLACE FUNCTION public.my_display_name()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(
    (SELECT full_name FROM students WHERE user_id = auth.uid() LIMIT 1),
    (SELECT full_name FROM teacher_directory WHERE user_id = auth.uid() LIMIT 1),
    (SELECT full_name FROM staff_whitelist sw JOIN auth.users u ON lower(u.email) = lower(sw.email) WHERE u.id = auth.uid() LIMIT 1),
    (SELECT NULLIF(full_name,'') FROM profiles WHERE id = auth.uid() AND position('@' in COALESCE(full_name,'')) = 0)
  )
$$;
REVOKE ALL ON FUNCTION public.my_display_name() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_display_name() TO authenticated;