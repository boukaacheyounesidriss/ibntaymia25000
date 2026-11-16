CREATE TABLE public.teacher_directory (
  code text PRIMARY KEY,
  full_name text NOT NULL,
  subject text NOT NULL,
  user_id uuid UNIQUE,
  login_email text,
  needs_review boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teacher_directory TO authenticated;
GRANT ALL ON public.teacher_directory TO service_role;
ALTER TABLE public.teacher_directory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "teacher dir read" ON public.teacher_directory FOR SELECT TO authenticated
  USING (public.is_management(auth.uid()) OR public.has_role(auth.uid(),'teacher'));
CREATE POLICY "teacher dir manage" ON public.teacher_directory FOR ALL TO authenticated
  USING (public.is_management(auth.uid())) WITH CHECK (public.is_management(auth.uid()));

CREATE OR REPLACE FUNCTION public.teacher_dir_sync_name()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.updated_at := now();
  IF NEW.user_id IS NOT NULL THEN
    UPDATE profiles SET full_name = NEW.full_name WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_teacher_dir_sync BEFORE INSERT OR UPDATE ON public.teacher_directory
  FOR EACH ROW EXECUTE FUNCTION public.teacher_dir_sync_name();
REVOKE EXECUTE ON FUNCTION public.teacher_dir_sync_name() FROM PUBLIC, anon, authenticated;