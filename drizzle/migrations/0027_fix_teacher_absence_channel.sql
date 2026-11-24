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
    'inapp', 'sent', NEW.teacher_id
  FROM public.user_roles ur
  WHERE ur.role IN ('admin','director','supervisor','digital_advisor') AND ur.user_id <> NEW.teacher_id;
  RETURN NEW;
END $$;