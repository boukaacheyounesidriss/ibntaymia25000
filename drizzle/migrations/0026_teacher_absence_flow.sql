CREATE OR REPLACE FUNCTION public.notify_management_teacher_absence()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _name text;
BEGIN
  SELECT full_name INTO _name FROM public.profiles WHERE id = NEW.teacher_id;
  INSERT INTO public.notifications (recipient_id, title, body, channel, status, created_by)
  SELECT DISTINCT ur.user_id, 'تصريح غياب أستاذ',
    coalesce(_name,'أستاذ') || ' — ' || to_char(NEW.absence_date,'YYYY-MM-DD') ||
    CASE WHEN NEW.slot_ids IS NULL THEN ' (اليوم كاملاً)' ELSE ' (' || array_length(NEW.slot_ids,1) || ' حصة)' END ||
    coalesce(' — ' || NEW.reason, ''),
    'in_app', 'sent', NEW.teacher_id
  FROM public.user_roles ur
  WHERE ur.role IN ('admin','director','supervisor','digital_advisor') AND ur.user_id <> NEW.teacher_id;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_teacher_absence ON public.teacher_absences;
CREATE TRIGGER trg_notify_teacher_absence AFTER INSERT ON public.teacher_absences
FOR EACH ROW EXECUTE FUNCTION public.notify_management_teacher_absence();

CREATE OR REPLACE FUNCTION public.block_absent_teacher_session()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.slot_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.teacher_absences a
    JOIN public.schedule_slots s ON s.id = NEW.slot_id
    WHERE a.absence_date = NEW.session_date AND a.teacher_id = s.teacher_id
      AND (a.slot_ids IS NULL OR NEW.slot_id = ANY(a.slot_ids))
  ) AND NOT EXISTS (
    SELECT 1 FROM public.free_period_decisions d
    WHERE d.slot_id = NEW.slot_id AND d.decision_date = NEW.session_date AND d.decision = 'substitute'
  ) THEN
    RAISE EXCEPTION 'هذه الحصة ملغاة لغياب الأستاذ المصرَّح به';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_block_absent_teacher_session ON public.attendance_sessions;
CREATE TRIGGER trg_block_absent_teacher_session BEFORE INSERT ON public.attendance_sessions
FOR EACH ROW EXECUTE FUNCTION public.block_absent_teacher_session();

CREATE OR REPLACE FUNCTION public.my_cancelled_slots(_from date, _to date)
RETURNS TABLE(slot_id uuid, class_id uuid, on_date date, reason text, decision text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH my_classes AS (
    SELECT st.class_id FROM public.students st
    WHERE st.class_id IS NOT NULL AND (st.user_id = auth.uid()
      OR st.id IN (SELECT ps.student_id FROM public.parent_student ps WHERE ps.parent_user_id = auth.uid()))
    UNION SELECT s2.class_id FROM public.schedule_slots s2 WHERE s2.teacher_id = auth.uid()
  ), days AS (SELECT generate_series(_from, least(_to, _from + 14), '1 day')::date AS d)
  SELECT s.id, s.class_id, days.d, a.reason, fd.decision
  FROM days
  JOIN public.schedule_slots s ON s.weekday = extract(dow FROM days.d)::int AND s.is_active
  JOIN public.teacher_absences a ON a.teacher_id = s.teacher_id AND a.absence_date = days.d
    AND (a.slot_ids IS NULL OR s.id = ANY(a.slot_ids))
  LEFT JOIN public.free_period_decisions fd ON fd.slot_id = s.id AND fd.decision_date = days.d
  WHERE s.class_id IN (SELECT class_id FROM my_classes) OR public.is_management(auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.my_cancelled_slots(date, date) TO authenticated;

DROP POLICY IF EXISTS "ta delete own" ON public.teacher_absences;
CREATE POLICY "ta delete own" ON public.teacher_absences FOR DELETE TO authenticated
USING (teacher_id = auth.uid() AND absence_date >= current_date);