
-- 1) class_teachers sync from schedule
INSERT INTO public.class_teachers (class_id, teacher_id, subject)
SELECT DISTINCT ON (s.class_id, s.teacher_id) s.class_id, s.teacher_id, s.subject
FROM public.schedule_slots s
WHERE s.teacher_id IS NOT NULL AND s.is_active
  AND NOT EXISTS (SELECT 1 FROM public.class_teachers ct WHERE ct.class_id = s.class_id AND ct.teacher_id = s.teacher_id);

CREATE OR REPLACE FUNCTION public.sync_class_teacher_from_slot() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.teacher_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM class_teachers WHERE class_id = NEW.class_id AND teacher_id = NEW.teacher_id) THEN
    INSERT INTO class_teachers(class_id, teacher_id, subject) VALUES (NEW.class_id, NEW.teacher_id, NEW.subject);
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_sync_class_teacher ON public.schedule_slots;
CREATE TRIGGER trg_sync_class_teacher AFTER INSERT OR UPDATE OF teacher_id, class_id ON public.schedule_slots
FOR EACH ROW EXECUTE FUNCTION public.sync_class_teacher_from_slot();

CREATE OR REPLACE FUNCTION public.teaches_class(_teacher uuid, _class uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM schedule_slots WHERE teacher_id = _teacher AND class_id = _class AND is_active)
      OR EXISTS (SELECT 1 FROM class_teachers WHERE teacher_id = _teacher AND class_id = _class)
$$;

-- 2) head teacher
ALTER TABLE public.classes ADD COLUMN IF NOT EXISTS head_teacher_id uuid;
CREATE OR REPLACE FUNCTION public.check_head_teacher() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.head_teacher_id IS NOT NULL AND NOT public.teaches_class(NEW.head_teacher_id, NEW.id) THEN
    RAISE EXCEPTION 'NOT_CLASS_TEACHER: الأستاذ الرئيسي يجب أن يكون ممن يدرّسون هذا القسم';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_check_head_teacher ON public.classes;
CREATE TRIGGER trg_check_head_teacher BEFORE INSERT OR UPDATE OF head_teacher_id ON public.classes
FOR EACH ROW EXECUTE FUNCTION public.check_head_teacher();

CREATE OR REPLACE FUNCTION public.set_class_head_teacher(_class uuid, _teacher uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT (public.is_management(auth.uid())) THEN RAISE EXCEPTION 'FORBIDDEN: للإدارة فقط' USING ERRCODE='42501'; END IF;
  UPDATE classes SET head_teacher_id = _teacher WHERE id = _class;
END $$;
GRANT EXECUTE ON FUNCTION public.set_class_head_teacher(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.teaches_class(uuid, uuid) TO authenticated;

-- 3) reception hours
CREATE TABLE public.teacher_reception_hours (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL,
  weekday smallint NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  place text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teacher_reception_hours TO authenticated;
GRANT ALL ON public.teacher_reception_hours TO service_role;
ALTER TABLE public.teacher_reception_hours ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reception read" ON public.teacher_reception_hours FOR SELECT TO authenticated USING (true);
CREATE POLICY "reception manage" ON public.teacher_reception_hours FOR ALL TO authenticated
  USING (teacher_id = auth.uid() OR public.is_management(auth.uid()))
  WITH CHECK (teacher_id = auth.uid() OR public.is_management(auth.uid()));

-- 4) teacher posts
CREATE TABLE public.teacher_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL DEFAULT auth.uid(),
  class_id uuid REFERENCES public.classes(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'lesson',
  title text NOT NULL,
  body text,
  link_url text,
  due_date date,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teacher_posts TO authenticated;
GRANT ALL ON public.teacher_posts TO service_role;
ALTER TABLE public.teacher_posts ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.check_teacher_post() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.kind NOT IN ('lesson','summary','homework','tip','opportunity','event') THEN RAISE EXCEPTION 'BAD_KIND'; END IF;
  IF NEW.class_id IS NOT NULL AND NOT public.is_management(auth.uid()) AND NOT public.teaches_class(NEW.teacher_id, NEW.class_id) THEN
    RAISE EXCEPTION 'NOT_CLASS_TEACHER: يمكنك النشر لأقسامك فقط';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_check_teacher_post BEFORE INSERT OR UPDATE ON public.teacher_posts
FOR EACH ROW EXECUTE FUNCTION public.check_teacher_post();
CREATE POLICY "posts read" ON public.teacher_posts FOR SELECT TO authenticated USING (
  teacher_id = auth.uid() OR public.is_management(auth.uid())
  OR class_id IS NULL
  OR EXISTS (SELECT 1 FROM students s WHERE s.class_id = teacher_posts.class_id AND s.user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM parent_student ps JOIN students s ON s.id = ps.student_id WHERE ps.parent_user_id = auth.uid() AND s.class_id = teacher_posts.class_id)
);
CREATE POLICY "posts write" ON public.teacher_posts FOR ALL TO authenticated
  USING (teacher_id = auth.uid() OR public.is_management(auth.uid()))
  WITH CHECK ((teacher_id = auth.uid() AND public.has_role(auth.uid(),'teacher')) OR public.is_management(auth.uid()));

-- 5) appointments
ALTER TABLE public.meeting_requests ADD COLUMN IF NOT EXISTS target_kind text NOT NULL DEFAULT 'administration';
ALTER TABLE public.meeting_requests ADD COLUMN IF NOT EXISTS target_teacher_id uuid;
CREATE POLICY "Teachers read own meeting requests" ON public.meeting_requests FOR SELECT TO authenticated
  USING (target_teacher_id = auth.uid());
CREATE POLICY "Teachers answer own meeting requests" ON public.meeting_requests FOR UPDATE TO authenticated
  USING (target_teacher_id = auth.uid()) WITH CHECK (target_teacher_id = auth.uid());

-- 6) parent/student view of child's teachers + reception hours
CREATE OR REPLACE FUNCTION public.my_children_teachers()
RETURNS TABLE(student_id uuid, student_name text, class_name text, teacher_id uuid, teacher_name text, subject text, is_head boolean, reception jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH kids AS (
    SELECT s.id, s.full_name, s.class_id FROM students s
    WHERE s.user_id = auth.uid() OR EXISTS (SELECT 1 FROM parent_student ps WHERE ps.student_id = s.id AND ps.parent_user_id = auth.uid())
  ), t AS (
    SELECT DISTINCT k.id kid, sl.teacher_id, sl.subject FROM kids k JOIN schedule_slots sl ON sl.class_id = k.class_id AND sl.is_active AND sl.teacher_id IS NOT NULL
  )
  SELECT k.id, k.full_name, c.name, t.teacher_id,
    COALESCE(td.full_name, p.full_name, 'أستاذ'), t.subject, (c.head_teacher_id = t.teacher_id),
    COALESCE((SELECT jsonb_agg(jsonb_build_object('weekday', r.weekday, 'start', to_char(r.start_time,'HH24:MI'), 'end', to_char(r.end_time,'HH24:MI'), 'place', r.place) ORDER BY r.weekday, r.start_time)
      FROM teacher_reception_hours r WHERE r.teacher_id = t.teacher_id), '[]'::jsonb)
  FROM kids k JOIN t ON t.kid = k.id JOIN classes c ON c.id = k.class_id
  LEFT JOIN profiles p ON p.id = t.teacher_id
  LEFT JOIN LATERAL (SELECT full_name FROM teacher_directory WHERE user_id = t.teacher_id LIMIT 1) td ON true
  ORDER BY k.full_name, t.subject
$$;
GRANT EXECUTE ON FUNCTION public.my_children_teachers() TO authenticated;
