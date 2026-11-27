CREATE TABLE public.site_maintenance (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled boolean NOT NULL DEFAULT false,
  message text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid
);
INSERT INTO public.site_maintenance (id) VALUES (true);
GRANT SELECT ON public.site_maintenance TO anon, authenticated;
GRANT UPDATE ON public.site_maintenance TO authenticated;
GRANT ALL ON public.site_maintenance TO service_role;
ALTER TABLE public.site_maintenance ENABLE ROW LEVEL SECURITY;
CREATE POLICY sm_read ON public.site_maintenance FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY sm_owner_upd ON public.site_maintenance FOR UPDATE TO authenticated USING ((select public.is_role_owner())) WITH CHECK ((select public.is_role_owner()));