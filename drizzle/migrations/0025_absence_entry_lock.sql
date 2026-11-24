CREATE OR REPLACE FUNCTION public.is_management(_uid uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT has_role(_uid,'admin') OR has_role(_uid,'director') OR has_role(_uid,'supervisor') OR has_role(_uid,'developer') OR has_role(_uid,'digital_advisor')
$$;

-- A student is locked out of class attendance while their latest absence is unjustified
-- and no entry permit was issued after it.
CREATE OR REPLACE FUNCTION public.student_entry_block(_sid uuid)
 RETURNS TABLE(since_date date, absences integer)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH last_ok AS (
    SELECT max(greatest(r.created_at)) AS t FROM attendance_records r
     WHERE r.student_id = _sid AND (r.status IN ('present','late') OR r.justified_at IS NOT NULL OR r.status = 'excused')
  ), last_permit AS (
    SELECT max(entry_time) AS t FROM entry_permits WHERE student_id = _sid
  ), pend AS (
    SELECT r.created_at, s.session_date FROM attendance_records r JOIN attendance_sessions s ON s.id = r.session_id
     WHERE r.student_id = _sid AND r.status = 'absent' AND r.justified_at IS NULL
       AND r.created_at > COALESCE((SELECT t FROM last_ok), '-infinity')
       AND r.created_at > COALESCE((SELECT t FROM last_permit), '-infinity')
  )
  SELECT min(session_date), count(*)::int FROM pend HAVING count(*) > 0
$$;

CREATE OR REPLACE FUNCTION public.class_blocked_students(_class uuid)
 RETURNS TABLE(student_id uuid, since_date date, absences integer)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NOT (is_management(auth.uid()) OR teaches_class(auth.uid(), _class)
          OR EXISTS (SELECT 1 FROM class_representatives WHERE user_id = auth.uid() AND class_id = _class)
          OR EXISTS (SELECT 1 FROM schedule_slots WHERE class_id = _class AND teacher_id = auth.uid())) THEN
    RAISE EXCEPTION 'PERM_DENIED' USING ERRCODE='42501';
  END IF;
  RETURN QUERY SELECT st.id, b.since_date, b.absences FROM students st
    CROSS JOIN LATERAL public.student_entry_block(st.id) b
   WHERE st.class_id = _class AND st.enrollment_status = 'active';
END $$;
REVOKE ALL ON FUNCTION public.class_blocked_students(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.class_blocked_students(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.student_entry_block(uuid) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.skip_blocked_student_record()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT is_management(auth.uid())
     AND EXISTS (SELECT 1 FROM public.student_entry_block(NEW.student_id)) THEN
    RETURN NULL; -- not recorded until management justifies or issues an entry permit
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_skip_blocked_student ON public.attendance_records;
CREATE TRIGGER trg_skip_blocked_student BEFORE INSERT ON public.attendance_records
 FOR EACH ROW EXECUTE FUNCTION public.skip_blocked_student_record();

-- Management justifies selected absence records directly
CREATE OR REPLACE FUNCTION public.justify_absences(_record_ids uuid[], _reason text)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE n int;
BEGIN
  IF NOT is_management(auth.uid()) THEN RAISE EXCEPTION 'PERM_DENIED: التبرير للإدارة فقط' USING ERRCODE='42501'; END IF;
  IF COALESCE(trim(_reason),'') = '' THEN RAISE EXCEPTION 'اكتب سبب التبرير'; END IF;
  UPDATE attendance_records SET justified_at = now(), justified_by = auth.uid(), justification_note = trim(_reason)
   WHERE id = ANY(_record_ids) AND justified_at IS NULL AND status IN ('absent','late');
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO profile_audit_log(user_id, action, details) VALUES (auth.uid(), 'justify_absences', jsonb_build_object('records', _record_ids, 'reason', _reason));
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.justify_absences(uuid[], text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.justify_absences(uuid[], text) TO authenticated;