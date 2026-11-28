CREATE OR REPLACE FUNCTION public.submit_teacher_attendance(_id uuid, _session jsonb, _marks jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$
DECLARE uid uuid := auth.uid(); existing public.attendance_sessions%rowtype; mark jsonb;
BEGIN
  IF uid IS NULL OR (_session->>'teacher_id')::uuid IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'PERM_DENIED: هذه الحصة ليست لحسابك' USING ERRCODE='42501';
  END IF;
  IF _id IS NULL OR jsonb_typeof(_marks) IS DISTINCT FROM 'array' OR jsonb_array_length(_marks) < 1 OR jsonb_array_length(_marks) > 200 THEN
    RAISE EXCEPTION 'قائمة الحضور غير صالحة';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(_marks) m WHERE COALESCE(m->>'status','') NOT IN ('present','absent','late') OR m->>'student_id' IS NULL) THEN
    RAISE EXCEPTION 'حالة حضور غير صالحة';
  END IF;
  IF (SELECT count(DISTINCT m->>'student_id') FROM jsonb_array_elements(_marks) m) <> jsonb_array_length(_marks) THEN
    RAISE EXCEPTION 'تلميذ مكرر';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(_id::text, 0));
  SELECT * INTO existing FROM public.attendance_sessions WHERE id = _id;
  IF FOUND THEN
    IF existing.teacher_id IS DISTINCT FROM uid OR existing.class_id IS DISTINCT FROM (_session->>'class_id')::uuid
      OR existing.session_date IS DISTINCT FROM (_session->>'session_date')::date
      OR existing.slot_id IS DISTINCT FROM NULLIF(_session->>'slot_id','')::uuid
      OR existing.group_scope IS DISTINCT FROM COALESCE(_session->>'group_scope','all') THEN
      RAISE EXCEPTION 'إيصال الحضور لا يطابق الحصة' USING ERRCODE='42501';
    END IF;
    RETURN _id;
  END IF;
  INSERT INTO public.attendance_sessions(id,class_id,teacher_id,session_date,period,subject,slot_id,session_type,group_scope,note)
  VALUES (_id,(_session->>'class_id')::uuid,uid,(_session->>'session_date')::date,_session->>'period',_session->>'subject',NULLIF(_session->>'slot_id','')::uuid,COALESCE(_session->>'session_type','regular'),COALESCE(_session->>'group_scope','all'),_session->>'note');
  FOR mark IN SELECT * FROM jsonb_array_elements(_marks) LOOP
    IF NOT EXISTS (SELECT 1 FROM public.students WHERE id = (mark->>'student_id')::uuid AND class_id = (_session->>'class_id')::uuid AND enrollment_status = 'active' AND (COALESCE(_session->>'group_scope','all') IN ('all','merged') OR subgroup = _session->>'group_scope')) THEN
      RAISE EXCEPTION 'التلميذ لا ينتمي إلى قسم وفوج الحصة' USING ERRCODE='42501';
    END IF;
    INSERT INTO public.attendance_records(session_id,student_id,status) VALUES (_id,(mark->>'student_id')::uuid,mark->>'status');
  END LOOP;
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.submit_teacher_attendance(uuid,jsonb,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_teacher_attendance(uuid,jsonb,jsonb) TO authenticated;