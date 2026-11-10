CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE public.class_representatives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('rep','deputy')),
  assigned_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (class_id, kind),
  UNIQUE (user_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.class_representatives TO authenticated;
GRANT ALL ON public.class_representatives TO service_role;
ALTER TABLE public.class_representatives ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reps read" ON public.class_representatives FOR SELECT TO authenticated
  USING (public.is_management(auth.uid()) OR user_id = auth.uid() OR public.has_role(auth.uid(),'teacher'));
CREATE POLICY "management writes reps" ON public.class_representatives FOR ALL TO authenticated
  USING (public.is_management(auth.uid())) WITH CHECK (public.is_management(auth.uid()));

CREATE OR REPLACE FUNCTION public.class_rep_before()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE st record;
BEGIN
  SELECT id, class_id, user_id, enrollment_status INTO st FROM students WHERE id = NEW.student_id;
  IF st.id IS NULL THEN RAISE EXCEPTION 'REP_NO_STUDENT'; END IF;
  IF st.user_id IS NULL THEN RAISE EXCEPTION 'REP_NO_ACCOUNT: التلميذ لا يملك حساباً بعد'; END IF;
  IF st.class_id IS DISTINCT FROM NEW.class_id THEN RAISE EXCEPTION 'REP_WRONG_CLASS: التلميذ ليس من هذا القسم'; END IF;
  IF st.enrollment_status <> 'active' THEN RAISE EXCEPTION 'REP_INACTIVE: التلميذ غير متمدرس'; END IF;
  NEW.user_id := st.user_id;
  NEW.assigned_by := auth.uid();
  RETURN NEW;
END $$;
CREATE TRIGGER trg_class_rep_before BEFORE INSERT OR UPDATE ON public.class_representatives
  FOR EACH ROW EXECUTE FUNCTION public.class_rep_before();

CREATE OR REPLACE FUNCTION public.class_rep_sync_roles()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    DELETE FROM user_roles WHERE user_id = OLD.user_id AND role IN ('class_rep','class_rep_deputy');
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') THEN
    INSERT INTO user_roles(user_id, role)
    VALUES (NEW.user_id, CASE WHEN NEW.kind='rep' THEN 'class_rep'::app_role ELSE 'class_rep_deputy'::app_role END)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER trg_class_rep_roles AFTER INSERT OR UPDATE OR DELETE ON public.class_representatives
  FOR EACH ROW EXECUTE FUNCTION public.class_rep_sync_roles();
REVOKE EXECUTE ON FUNCTION public.class_rep_before() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.class_rep_sync_roles() FROM PUBLIC, anon, authenticated;

CREATE TABLE public.teacher_attendance_pins (
  teacher_id uuid PRIMARY KEY,
  pin_hash text NOT NULL,
  failed_count integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.teacher_attendance_pins TO service_role;
ALTER TABLE public.teacher_attendance_pins ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.set_my_attendance_pin(_pin text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT has_role(auth.uid(),'teacher') THEN
    RAISE EXCEPTION 'PERM_DENIED: الرمز خاص بالأساتذة' USING ERRCODE='42501'; END IF;
  IF _pin !~ '^[0-9]{4,6}$' THEN RAISE EXCEPTION 'PIN_FORMAT: الرمز من 4 إلى 6 أرقام'; END IF;
  IF _pin ~ '^(\d)\1+$' OR _pin IN ('1234','12345','123456','4321','54321','654321','0123') THEN
    RAISE EXCEPTION 'PIN_WEAK: اختر رمزاً أقل سهولة'; END IF;
  INSERT INTO teacher_attendance_pins(teacher_id, pin_hash, failed_count, locked_until, updated_at)
  VALUES (auth.uid(), crypt(_pin, gen_salt('bf')), 0, NULL, now())
  ON CONFLICT (teacher_id) DO UPDATE SET pin_hash = EXCLUDED.pin_hash, failed_count = 0, locked_until = NULL, updated_at = now();
  INSERT INTO profile_audit_log(user_id, action) VALUES (auth.uid(), 'attendance_pin_set');
END $$;

CREATE OR REPLACE FUNCTION public.has_my_attendance_pin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM teacher_attendance_pins WHERE teacher_id = auth.uid())
$$;

CREATE OR REPLACE FUNCTION public.reset_teacher_attendance_pin(_teacher uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_management(auth.uid()) THEN RAISE EXCEPTION 'PERM_DENIED' USING ERRCODE='42501'; END IF;
  DELETE FROM teacher_attendance_pins WHERE teacher_id = _teacher;
END $$;

CREATE OR REPLACE FUNCTION public.kiosk_context()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE rep record; cname text; now_l timestamp := (now() AT TIME ZONE 'Africa/Algiers'); sl record; tname text; done boolean := false;
BEGIN
  SELECT * INTO rep FROM class_representatives WHERE user_id = auth.uid();
  IF rep.id IS NULL THEN RAISE EXCEPTION 'NOT_REP: هذه الشاشة لمسؤول القسم ونائبه فقط' USING ERRCODE='42501'; END IF;
  SELECT name INTO cname FROM classes WHERE id = rep.class_id;
  SELECT s.* INTO sl FROM schedule_slots s
   WHERE s.class_id = rep.class_id AND s.is_active AND s.weekday = extract(dow FROM now_l)::int
     AND now_l::time BETWEEN s.start_time - interval '10 minutes' AND s.end_time + interval '20 minutes'
   ORDER BY s.start_time LIMIT 1;
  IF sl.id IS NOT NULL THEN
    SELECT full_name INTO tname FROM profiles WHERE id = sl.teacher_id;
    done := EXISTS (SELECT 1 FROM attendance_sessions a WHERE a.class_id = rep.class_id AND a.session_date = now_l::date
      AND COALESCE(NULLIF(btrim(a.period),''),'') = COALESCE(sl.period_no::text, to_char(sl.start_time,'HH24:MI')));
  END IF;
  RETURN jsonb_build_object(
    'class_id', rep.class_id, 'class_name', cname, 'kind', rep.kind, 'today', now_l::date,
    'slot', CASE WHEN sl.id IS NULL THEN NULL ELSE jsonb_build_object('id', sl.id, 'subject', sl.subject,
      'start', to_char(sl.start_time,'HH24:MI'), 'end', to_char(sl.end_time,'HH24:MI'), 'period_no', sl.period_no,
      'teacher_name', COALESCE(tname,'غير مسند'), 'already_done', done) END,
    'students', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', st.id, 'name', st.full_name) ORDER BY st.full_name)
      FROM students st WHERE st.class_id = rep.class_id AND st.enrollment_status = 'active'), '[]'::jsonb));
END $$;

-- Wrong PIN returns an error object (not an exception) so the failure counter persists.
CREATE OR REPLACE FUNCTION public.kiosk_submit_attendance(_slot_id uuid, _absent uuid[], _late uuid[], _pin text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE rep record; sl record; now_l timestamp := (now() AT TIME ZONE 'Africa/Algiers'); signer uuid; p record;
  per text; sid uuid; n int; fails int;
BEGIN
  SELECT * INTO rep FROM class_representatives WHERE user_id = auth.uid();
  IF rep.id IS NULL THEN RAISE EXCEPTION 'NOT_REP: غير مسموح' USING ERRCODE='42501'; END IF;
  SELECT * INTO sl FROM schedule_slots WHERE id = _slot_id AND class_id = rep.class_id AND is_active;
  IF sl.id IS NULL THEN RAISE EXCEPTION 'BAD_SLOT: الحصة لا تخص هذا القسم'; END IF;
  IF sl.weekday <> extract(dow FROM now_l)::int
     OR now_l::time NOT BETWEEN sl.start_time - interval '10 minutes' AND sl.end_time + interval '20 minutes' THEN
    RAISE EXCEPTION 'OUT_OF_TIME: انتهى وقت إمضاء هذه الحصة، راجع الإدارة'; END IF;

  SELECT substitute_teacher_id INTO signer FROM free_period_decisions
   WHERE slot_id = sl.id AND decision_date = now_l::date AND decision = 'substitute' AND substitute_teacher_id IS NOT NULL LIMIT 1;
  IF signer IS NULL THEN
    SELECT substitute_teacher_id INTO signer FROM substitution_requests
     WHERE slot_id = sl.id AND request_date = now_l::date AND status = 'approved' AND substitute_teacher_id IS NOT NULL LIMIT 1;
  END IF;
  signer := COALESCE(signer, sl.teacher_id);
  IF signer IS NULL THEN RAISE EXCEPTION 'NO_TEACHER: لا يوجد أستاذ مسند لهذه الحصة، راجع الإدارة'; END IF;

  SELECT * INTO p FROM teacher_attendance_pins WHERE teacher_id = signer FOR UPDATE;
  IF p.teacher_id IS NULL THEN RAISE EXCEPTION 'NO_PIN: الأستاذ لم يُنشئ رمز الإمضاء بعد (من صفحة حسابه)'; END IF;
  IF p.locked_until IS NOT NULL AND p.locked_until > now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'PIN_LOCKED', 'minutes', ceil(extract(epoch FROM p.locked_until - now())/60)::int);
  END IF;
  IF p.pin_hash <> crypt(COALESCE(_pin,''), p.pin_hash) THEN
    fails := CASE WHEN p.locked_until IS NOT NULL THEN 1 ELSE p.failed_count + 1 END;
    UPDATE teacher_attendance_pins SET failed_count = CASE WHEN fails >= 3 THEN 0 ELSE fails END,
      locked_until = CASE WHEN fails >= 3 THEN now() + interval '15 minutes' ELSE NULL END
     WHERE teacher_id = signer;
    INSERT INTO profile_audit_log(user_id, action, details)
    VALUES (auth.uid(), 'kiosk_pin_failed', jsonb_build_object('teacher_id', signer, 'slot_id', sl.id, 'attempt', fails));
    IF fails >= 3 THEN
      INSERT INTO notifications (recipient_id, recipient_label, title, body, channel, status, created_by)
      SELECT DISTINCT ur.user_id, 'management', 'تنبيه أمني: محاولات رمز خاطئة',
        format('3 محاولات خاطئة لرمز إمضاء الحضور في القسم %s (حصة %s). قُفل الرمز 15 دقيقة.',
          (SELECT name FROM classes WHERE id = sl.class_id), sl.subject), 'inapp', 'sent', auth.uid()
      FROM user_roles ur WHERE ur.role IN ('admin','supervisor');
      RETURN jsonb_build_object('ok', false, 'error', 'PIN_LOCKED', 'minutes', 15);
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'PIN_WRONG', 'remaining', 3 - fails);
  END IF;

  UPDATE teacher_attendance_pins SET failed_count = 0, locked_until = NULL WHERE teacher_id = signer;
  per := COALESCE(sl.period_no::text, to_char(sl.start_time,'HH24:MI'));
  IF EXISTS (SELECT 1 FROM attendance_sessions a WHERE a.class_id = sl.class_id AND a.session_date = now_l::date
      AND COALESCE(NULLIF(btrim(a.period),''),'') = per) THEN
    RAISE EXCEPTION 'SESSION_EXISTS: حضور هذه الحصة مسجل مسبقاً، للتعديل راجع الإدارة';
  END IF;

  PERFORM set_config('app.kiosk_signed', '1', true);
  INSERT INTO attendance_sessions(class_id, teacher_id, session_date, period, subject, slot_id, session_type, note)
  VALUES (sl.class_id, signer, now_l::date, per, sl.subject, sl.id, 'regular',
          'إمضاء بالرمز عبر جهاز القسم (' || CASE rep.kind WHEN 'rep' THEN 'مسؤول القسم' ELSE 'نائب المسؤول' END || ')')
  RETURNING id INTO sid;
  INSERT INTO attendance_records(session_id, student_id, status)
  SELECT sid, st.id, CASE WHEN st.id = ANY(COALESCE(_absent,'{}')) THEN 'absent'
                          WHEN st.id = ANY(COALESCE(_late,'{}')) THEN 'late' ELSE 'present' END
  FROM students st WHERE st.class_id = sl.class_id AND st.enrollment_status = 'active';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.kiosk_signed', '', true);
  INSERT INTO profile_audit_log(user_id, action, details)
  VALUES (signer, 'kiosk_attendance_signed', jsonb_build_object('session_id', sid, 'device_user', auth.uid()));
  RETURN jsonb_build_object('ok', true, 'session_id', sid, 'count', n,
    'absent', COALESCE(array_length(_absent,1),0), 'late', COALESCE(array_length(_late,1),0), 'subject', sl.subject);
END $$;

REVOKE EXECUTE ON FUNCTION public.set_my_attendance_pin(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_my_attendance_pin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reset_teacher_attendance_pin(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.kiosk_context() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.kiosk_submit_attendance(uuid, uuid[], uuid[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_attendance_pin(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_my_attendance_pin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_teacher_attendance_pin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.kiosk_context() TO authenticated;
GRANT EXECUTE ON FUNCTION public.kiosk_submit_attendance(uuid, uuid[], uuid[], text) TO authenticated;

-- Allow PIN-signed kiosk inserts (flag only settable inside kiosk_submit_attendance)
CREATE OR REPLACE FUNCTION public.enforce_session_permissions()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE uid uuid := auth.uid(); win numeric; back numeric;
BEGIN
  IF TG_OP = 'INSERT' AND current_setting('app.kiosk_signed', true) = '1' THEN RETURN NEW; END IF;
  IF uid IS NULL OR is_management(uid) THEN RETURN COALESCE(NEW, OLD); END IF;
  IF TG_OP = 'INSERT' THEN
    IF NOT has_permission(uid,'attendance.take') THEN
      RAISE EXCEPTION 'PERM_DENIED: غير مسموح لك بتسجيل الحضور' USING ERRCODE='42501'; END IF;
    IF NEW.session_type='replacement' AND NOT has_permission(uid,'attendance.replacement') THEN
      RAISE EXCEPTION 'PERM_DENIED: الاستخلاف غير مسموح لحسابك' USING ERRCODE='42501'; END IF;
    IF NEW.session_type='extra' AND NOT has_permission(uid,'attendance.extra') THEN
      RAISE EXCEPTION 'PERM_DENIED: الحصص الإضافية غير مسموحة لحسابك' USING ERRCODE='42501'; END IF;
    SELECT value INTO back FROM access_settings WHERE key='attendance_backdate_days';
    IF back IS NOT NULL AND back >= 0 AND NEW.session_date < (current_date - back::int) THEN
      RAISE EXCEPTION 'PERM_DENIED: لا يمكن تسجيل حضور لتاريخ أقدم من % أيام', back::int USING ERRCODE='42501'; END IF;
    IF NEW.session_date > current_date THEN
      RAISE EXCEPTION 'PERM_DENIED: لا يمكن تسجيل حضور لتاريخ مستقبلي' USING ERRCODE='42501'; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF NOT has_permission(uid,'attendance.delete_session') THEN
      RAISE EXCEPTION 'PERM_DENIED: حذف جلسة الحضور غير مسموح لحسابك' USING ERRCODE='42501'; END IF;
    RETURN OLD;
  END IF;
  IF NOT has_permission(uid,'attendance.edit_after_save') THEN
    RAISE EXCEPTION 'PERM_DENIED: تعديل الحضور بعد الحفظ غير مسموح لحسابك' USING ERRCODE='42501'; END IF;
  SELECT value INTO win FROM access_settings WHERE key='attendance_edit_window_hours';
  IF win IS NOT NULL AND win > 0 AND OLD.created_at < now() - make_interval(hours => win::int) THEN
    RAISE EXCEPTION 'PERM_DENIED: انتهت المدة المسموحة للتعديل (% ساعة)', win::int USING ERRCODE='42501'; END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.enforce_record_permissions()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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