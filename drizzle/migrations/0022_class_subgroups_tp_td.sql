ALTER TABLE public.students ADD COLUMN IF NOT EXISTS subgroup text;
ALTER TABLE public.students ADD CONSTRAINT students_subgroup_chk CHECK (subgroup IS NULL OR subgroup IN ('g1','g2'));
ALTER TABLE public.attendance_sessions ADD COLUMN IF NOT EXISTS group_scope text NOT NULL DEFAULT 'all';
ALTER TABLE public.attendance_sessions ADD CONSTRAINT attendance_sessions_scope_chk CHECK (group_scope IN ('all','g1','g2','merged'));

DROP INDEX IF EXISTS public.attendance_sessions_class_date_period_unique;
CREATE UNIQUE INDEX attendance_sessions_class_date_period_scope_unique ON public.attendance_sessions
  (class_id, session_date, COALESCE(NULLIF(btrim(period), ''), ''), group_scope);

CREATE OR REPLACE FUNCTION public.check_session_group_scope() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(NEW.class_id::text || NEW.session_date::text));
  IF EXISTS (SELECT 1 FROM attendance_sessions a WHERE a.id <> NEW.id AND a.class_id = NEW.class_id
      AND a.session_date = NEW.session_date
      AND COALESCE(NULLIF(btrim(a.period),''),'') = COALESCE(NULLIF(btrim(NEW.period),''),'')
      AND (a.group_scope IN ('all','merged') OR NEW.group_scope IN ('all','merged') OR a.group_scope = NEW.group_scope)) THEN
    RAISE EXCEPTION 'SESSION_EXISTS: حضور هذه الحصة (أو أحد أفواجها) مسجل مسبقاً' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_session_group_scope ON public.attendance_sessions;
CREATE TRIGGER trg_session_group_scope BEFORE INSERT OR UPDATE OF class_id, session_date, period, group_scope
  ON public.attendance_sessions FOR EACH ROW EXECUTE FUNCTION public.check_session_group_scope();

CREATE OR REPLACE FUNCTION public.set_student_subgroup(_student uuid, _group text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cid uuid;
BEGIN
  IF _group IS NOT NULL AND _group NOT IN ('g1','g2') THEN RAISE EXCEPTION 'BAD_GROUP'; END IF;
  SELECT class_id INTO cid FROM students WHERE id = _student;
  IF cid IS NULL THEN RAISE EXCEPTION 'NOT_FOUND: التلميذ غير موجود'; END IF;
  IF NOT (is_management(auth.uid()) OR teaches_class(auth.uid(), cid)) THEN
    RAISE EXCEPTION 'PERM_DENIED: لا تدرّس هذا القسم' USING ERRCODE = '42501'; END IF;
  UPDATE students SET subgroup = _group WHERE id = _student;
END $$;

CREATE OR REPLACE FUNCTION public.auto_split_class_subgroups(_class uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n int; half int;
BEGIN
  IF NOT (is_management(auth.uid()) OR teaches_class(auth.uid(), _class)) THEN
    RAISE EXCEPTION 'PERM_DENIED: لا تدرّس هذا القسم' USING ERRCODE = '42501'; END IF;
  SELECT count(*) INTO n FROM students WHERE class_id = _class AND enrollment_status = 'active';
  half := ceil(n / 2.0);
  UPDATE students s SET subgroup = CASE WHEN r.rn <= half THEN 'g1' ELSE 'g2' END
  FROM (SELECT id, row_number() OVER (ORDER BY full_name) rn FROM students
        WHERE class_id = _class AND enrollment_status = 'active') r
  WHERE s.id = r.id;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION public.set_slot_group(_slot uuid, _group text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t uuid;
BEGIN
  IF _group NOT IN ('all','g1','g2') THEN RAISE EXCEPTION 'BAD_GROUP'; END IF;
  SELECT teacher_id INTO t FROM schedule_slots WHERE id = _slot;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF NOT (is_management(auth.uid()) OR t = auth.uid()) THEN
    RAISE EXCEPTION 'PERM_DENIED: هذه الحصة ليست لك' USING ERRCODE = '42501'; END IF;
  UPDATE schedule_slots SET group_label = _group, updated_at = now() WHERE id = _slot;
END $$;

REVOKE ALL ON FUNCTION public.set_student_subgroup(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.auto_split_class_subgroups(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_slot_group(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_student_subgroup(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.auto_split_class_subgroups(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_slot_group(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.kiosk_context()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
      AND COALESCE(NULLIF(btrim(a.period),''),'') = COALESCE(sl.period_no::text, to_char(sl.start_time,'HH24:MI'))
      AND (sl.group_label = 'all' OR a.group_scope IN ('all','merged') OR a.group_scope = sl.group_label));
  END IF;
  RETURN jsonb_build_object(
    'class_id', rep.class_id, 'class_name', cname, 'kind', rep.kind, 'today', now_l::date,
    'slot', CASE WHEN sl.id IS NULL THEN NULL ELSE jsonb_build_object('id', sl.id, 'subject', sl.subject,
      'start', to_char(sl.start_time,'HH24:MI'), 'end', to_char(sl.end_time,'HH24:MI'), 'period_no', sl.period_no,
      'group_label', sl.group_label,
      'teacher_name', COALESCE(tname,'غير مسند'), 'already_done', done) END,
    'students', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', st.id, 'name', st.full_name, 'subgroup', st.subgroup) ORDER BY st.full_name)
      FROM students st WHERE st.class_id = rep.class_id AND st.enrollment_status = 'active'), '[]'::jsonb));
END $function$;

DROP FUNCTION IF EXISTS public.kiosk_submit_attendance(uuid, uuid[], uuid[], text);
CREATE FUNCTION public.kiosk_submit_attendance(_slot_id uuid, _absent uuid[], _late uuid[], _pin text, _scope text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
DECLARE rep record; sl record; now_l timestamp := (now() AT TIME ZONE 'Africa/Algiers'); signer uuid; p record;
  per text; sid uuid; n int; fails int; sc text;
BEGIN
  SELECT * INTO rep FROM class_representatives WHERE user_id = auth.uid();
  IF rep.id IS NULL THEN RAISE EXCEPTION 'NOT_REP: غير مسموح' USING ERRCODE='42501'; END IF;
  SELECT * INTO sl FROM schedule_slots WHERE id = _slot_id AND class_id = rep.class_id AND is_active;
  IF sl.id IS NULL THEN RAISE EXCEPTION 'BAD_SLOT: الحصة لا تخص هذا القسم'; END IF;
  IF sl.weekday <> extract(dow FROM now_l)::int
     OR now_l::time NOT BETWEEN sl.start_time - interval '10 minutes' AND sl.end_time + interval '20 minutes' THEN
    RAISE EXCEPTION 'OUT_OF_TIME: انتهى وقت إمضاء هذه الحصة، راجع الإدارة'; END IF;
  sc := COALESCE(_scope, sl.group_label, 'all');
  IF sc NOT IN ('all','g1','g2','merged') THEN RAISE EXCEPTION 'BAD_GROUP'; END IF;
  IF sc IN ('g1','g2') AND NOT EXISTS (SELECT 1 FROM students WHERE class_id = sl.class_id AND enrollment_status='active' AND subgroup = sc) THEN
    RAISE EXCEPTION 'NO_GROUP: لم يُوزَّع تلاميذ هذا الفوج بعد، اطلب من الأستاذ أو الإدارة تقسيم الأفواج'; END IF;

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

  PERFORM set_config('app.kiosk_signed', '1', true);
  INSERT INTO attendance_sessions(class_id, teacher_id, session_date, period, subject, slot_id, session_type, note, group_scope)
  VALUES (sl.class_id, signer, now_l::date, per, sl.subject, sl.id, 'regular',
          'إمضاء بالرمز عبر جهاز القسم (' || CASE rep.kind WHEN 'rep' THEN 'مسؤول القسم' ELSE 'نائب المسؤول' END || ')'
          || CASE sc WHEN 'merged' THEN ' — حصة مجمّعة استثنائياً للفوجين' WHEN 'g1' THEN ' — الفوج 1' WHEN 'g2' THEN ' — الفوج 2' ELSE '' END, sc)
  RETURNING id INTO sid;
  INSERT INTO attendance_records(session_id, student_id, status)
  SELECT sid, st.id, CASE WHEN st.id = ANY(COALESCE(_absent,'{}')) THEN 'absent'
                          WHEN st.id = ANY(COALESCE(_late,'{}')) THEN 'late' ELSE 'present' END
  FROM students st WHERE st.class_id = sl.class_id AND st.enrollment_status = 'active'
    AND (sc IN ('all','merged') OR st.subgroup = sc);
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.kiosk_signed', '', true);
  INSERT INTO profile_audit_log(user_id, action, details)
  VALUES (signer, 'kiosk_attendance_signed', jsonb_build_object('session_id', sid, 'device_user', auth.uid(), 'scope', sc));
  RETURN jsonb_build_object('ok', true, 'session_id', sid, 'count', n,
    'absent', COALESCE(array_length(_absent,1),0), 'late', COALESCE(array_length(_late,1),0), 'subject', sl.subject);
END $function$;
REVOKE ALL ON FUNCTION public.kiosk_submit_attendance(uuid, uuid[], uuid[], text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.kiosk_submit_attendance(uuid, uuid[], uuid[], text, text) TO authenticated;