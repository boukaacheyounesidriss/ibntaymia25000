ALTER TABLE public.teacher_posts ADD COLUMN IF NOT EXISTS attachments jsonb NOT NULL DEFAULT '[]'::jsonb;
CREATE OR REPLACE FUNCTION public.check_lesson_attachments() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE a jsonb;
BEGIN
 IF jsonb_typeof(NEW.attachments) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'INVALID_ATTACHMENTS'; END IF;
 FOR a IN SELECT value FROM jsonb_array_elements(NEW.attachments) LOOP
  IF jsonb_typeof(a) IS DISTINCT FROM 'object' OR (a->>'path') IS NULL OR (a->>'name') IS NULL OR (a->>'type') IS NULL OR jsonb_typeof(a->'size') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'INVALID_ATTACHMENT'; END IF;
  IF (a->>'path') NOT LIKE NEW.teacher_id::text || '/' || NEW.id::text || '/%' OR (a->>'path') LIKE '%..%' THEN RAISE EXCEPTION 'INVALID_ATTACHMENT_OWNER'; END IF;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_check_lesson_attachments BEFORE INSERT OR UPDATE ON public.teacher_posts FOR EACH ROW EXECUTE FUNCTION public.check_lesson_attachments();
CREATE POLICY "teachers upload lesson files" ON storage.objects FOR INSERT TO authenticated WITH CHECK (
 bucket_id = 'teacher-lessons' AND (storage.foldername(name))[1] = auth.uid()::text AND public.has_role(auth.uid(),'teacher')
);
CREATE POLICY "lesson files visible to post readers" ON storage.objects FOR SELECT TO authenticated USING (
 bucket_id = 'teacher-lessons' AND ((storage.foldername(name))[1] = auth.uid()::text OR EXISTS (
 SELECT 1 FROM public.teacher_posts p WHERE p.attachments @> jsonb_build_array(jsonb_build_object('path', storage.objects.name))
 ))
);
CREATE POLICY "authors remove lesson files" ON storage.objects FOR DELETE TO authenticated USING (
 bucket_id = 'teacher-lessons' AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_management(auth.uid()))
);
