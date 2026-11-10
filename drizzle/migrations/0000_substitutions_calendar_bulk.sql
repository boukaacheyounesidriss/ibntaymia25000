-- Consolidated base schema imported from the original project's supabase/migrations (fresh database).
-- >>> 20260516201429_16c18c4b-8c17-412a-87cf-2df6d2626647.sql
-- Roles enum
CREATE TYPE public.app_role AS ENUM ('admin', 'director', 'supervisor', 'teacher', 'parent', 'student', 'gate_monitor');

-- Profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  preferred_language TEXT DEFAULT 'ar',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- User roles table (security: roles MUST be in separate table)
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Security definer function to check roles (prevents RLS recursion)
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

-- Function to get all roles for a user
CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id UUID)
RETURNS SETOF app_role
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.user_roles WHERE user_id = _user_id
$$;

-- RLS: profiles
CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));

-- RLS: user_roles
CREATE POLICY "Users can view own roles" ON public.user_roles
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all roles" ON public.user_roles
  FOR ALL USING (public.has_role(auth.uid(), 'admin'));

-- Auto-create profile + default 'student' role on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, preferred_language)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'preferred_language', 'ar')
  );

  -- Default role: student (admin can change later)
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'student');

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- updated_at trigger for profiles
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
;
-- >>> 20260516201517_f0a27cab-a5d6-4314-8065-9a270b821982.sql
-- Fix search_path on trigger functions
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- Revoke public execute on definer functions; grant only to needed roles
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(UUID, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_roles(UUID) FROM PUBLIC, anon;
-- has_role and get_user_roles must remain executable by authenticated users (used in RLS and app)
GRANT EXECUTE ON FUNCTION public.has_role(UUID, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_roles(UUID) TO authenticated;
;
-- >>> 20260517080404_448ff88c-3c6c-463e-8998-64347a9bd392.sql
-- Classes table
CREATE TABLE IF NOT EXISTS public.classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  level text,
  branch text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone authenticated can view classes" ON public.classes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage classes" ON public.classes FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'));

-- Students table
CREATE TABLE IF NOT EXISTS public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  gender text CHECK (gender IN ('M','F')),
  date_of_birth date,
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  fake_email text,
  fake_phone text,
  user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_students_class ON public.students(class_id);
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view students" ON public.students FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff manage students" ON public.students FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));

CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Staff whitelist
CREATE TABLE IF NOT EXISTS public.staff_whitelist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL UNIQUE,
  role app_role NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.staff_whitelist ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage staff whitelist" ON public.staff_whitelist FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- Updated signup trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _name text;
  _whitelisted_role app_role;
BEGIN
  _name := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email);
  INSERT INTO public.profiles (id, full_name, preferred_language)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'));

  SELECT role INTO _whitelisted_role FROM public.staff_whitelist
  WHERE full_name = _name LIMIT 1;

  IF _whitelisted_role IS NOT NULL THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, _whitelisted_role);
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'student');
  END IF;

  UPDATE public.students SET user_id = NEW.id WHERE full_name = _name AND user_id IS NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Enable realtime
ALTER TABLE public.classes REPLICA IDENTITY FULL;
ALTER TABLE public.students REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.classes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.students;

-- Whitelist Bouqaach
INSERT INTO public.staff_whitelist (full_name, role, note)
VALUES ('بوكعاش يونس إدريس', 'admin', 'مسؤول رئيسي')
ON CONFLICT (full_name) DO UPDATE SET role = EXCLUDED.role;

-- Seed classes
INSERT INTO public.classes (name, level, branch) VALUES ('ج م ع ت 4', '1AS', 'جذع مشترك علوم وتكنولوجيا') ON CONFLICT (name) DO NOTHING;
INSERT INTO public.classes (name, level, branch) VALUES ('ج م أ 1', '1AS', 'جذع مشترك آداب') ON CONFLICT (name) DO NOTHING;

-- Seed students class 1 (ج م ع ت 4)
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ابن خرورو عبد الرحمان','M','2009-11-05', id, 'student93810@idaroom.test','+213524942603' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ابن مناح أروى','F','2010-11-03', id, 'student13278@idaroom.test','+213546913810' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن جامع أريج نور الهدى','F','2010-12-01', id, 'student42098@idaroom.test','+213539958838' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن سماعين بلال','M','2010-08-13', id, 'student28289@idaroom.test','+213523756669' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن عامر رنيم','F','2010-06-21', id, 'student98696@idaroom.test','+213583197857' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن قدواد ندى حبيبة','F','2010-09-14', id, 'student21395@idaroom.test','+213589254563' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوزيتونة ليله','F','2011-03-23', id, 'student65302@idaroom.test','+213514265799' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوعبيد ملاك','F','2010-01-05', id, 'student13905@idaroom.test','+213522575562' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوعصيدة أمينة','F','2010-04-10', id, 'student38657@idaroom.test','+213541227216' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوكعاش يونس إدريس','M','2011-03-07', id, 'student76237@idaroom.test','+213590801586' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'حركاتي محمد الصالح','M','2009-05-06', id, 'student13478@idaroom.test','+213585329037' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'حيرش محمد تميم','M','2010-11-04', id, 'student36062@idaroom.test','+213597226012' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'خناوي ألاء الرحمان','F','2010-06-07', id, 'student81426@idaroom.test','+213566306997' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'خيري نسرين','F','2011-01-19', id, 'student38893@idaroom.test','+213570291817' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سوالمية محمد الصالح','M','2009-04-06', id, 'student87236@idaroom.test','+213547338124' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شكارلي محمد بهاء الدين','M','2010-09-11', id, 'student10851@idaroom.test','+213531429110' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شوابية قصي','M','2010-10-21', id, 'student65392@idaroom.test','+213555667651' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عباس حداد فزيل مولود','M','2010-06-15', id, 'student46421@idaroom.test','+213530868105' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عبد الرزاق يوسف','M','2010-07-06', id, 'student38221@idaroom.test','+213555176955' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عمرو عياش أنفال','F','2011-01-24', id, 'student23396@idaroom.test','+213522448136' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'فاضل اياد شمس الدين','M','2010-07-30', id, 'student59797@idaroom.test','+213522981052' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قادة أمنية','F','2010-07-05', id, 'student57052@idaroom.test','+213556164955' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قجال رائد نزار','M','2010-01-10', id, 'student89131@idaroom.test','+213545503389' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قروي جهينة أناييس','F','2010-06-09', id, 'student15695@idaroom.test','+213571662963' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قليل نور مايا','F','2010-10-09', id, 'student80284@idaroom.test','+213526753883' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'كحول زكريا','M','2010-05-27', id, 'student59615@idaroom.test','+213520576383' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'كحول يحي','M','2010-05-27', id, 'student82357@idaroom.test','+213549349722' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'لعور نريمان','F','2010-03-18', id, 'student92397@idaroom.test','+213593016315' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'منتوري نادر','M','2010-01-18', id, 'student57400@idaroom.test','+213587490893' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ميمون عبد الله','M','2010-09-19', id, 'student35203@idaroom.test','+213519335534' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ميمون نجيب','M','2009-06-07', id, 'student16006@idaroom.test','+213598753260' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'يخلف إياد عبد الرحيم','M','2010-08-12', id, 'student39871@idaroom.test','+213548840994' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'تواتي إيناس','F','2010-01-01', id, 'student20458@idaroom.test','+213541244663' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قدوري إيناس','F','2010-01-01', id, 'student23238@idaroom.test','+213561019678' FROM public.classes WHERE name='ج م ع ت 4' LIMIT 1;

-- Seed students class 2 (ج م أ 1)
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'الخزعلي علي','M','2010-11-16', id, 'student56566@idaroom.test','+213538119557' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن جامع عبدالرحمان','M','2009-03-19', id, 'student97841@idaroom.test','+213545833156' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن فضة اسيل ندي الريحان','F','2011-01-30', id, 'student99593@idaroom.test','+213596977837' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن فيسح عائشة','F','2011-03-05', id, 'student19358@idaroom.test','+213591756179' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوخالفة رامي','M','2010-11-10', id, 'student93227@idaroom.test','+213532969840' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوخالفة هارون الرشيد','M','2009-10-17', id, 'student80010@idaroom.test','+213542857966' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بودرياسي إبراهيم خليل','M','2009-09-29', id, 'student31417@idaroom.test','+213572043515' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بودفة زينب','F','2007-05-17', id, 'student59735@idaroom.test','+213546231783' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوسالم رنا مرام','F','2010-09-03', id, 'student93886@idaroom.test','+213584752529' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوشيلاون محمد وليد','M','2010-11-27', id, 'student38785@idaroom.test','+213553524491' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوكرو حمزة','M','2010-03-19', id, 'student17331@idaroom.test','+213540742311' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوهيدل سراج الدين','M','2010-04-08', id, 'student14207@idaroom.test','+213552339391' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'جبلية رقية لجين','F','2010-01-03', id, 'student62581@idaroom.test','+213545935572' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'جلواط سامي شعيب','M','2009-06-24', id, 'student18675@idaroom.test','+213538317637' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'خنفوسي محمد فراس','M','2010-04-25', id, 'student84341@idaroom.test','+213552235350' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'دالي ريم','F','2011-02-03', id, 'student37869@idaroom.test','+213597971488' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'دحدوح شعيب','M','2008-09-15', id, 'student75435@idaroom.test','+213563100814' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'رزاق اية','F','2010-07-22', id, 'student94259@idaroom.test','+213571586053' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سبيح دينا نورهان','F','2008-08-03', id, 'student28726@idaroom.test','+213545551614' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سوفي عبد المعز','M','2009-06-02', id, 'student28301@idaroom.test','+213543101783' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سيابة شيماء شروق','F','2010-07-05', id, 'student83579@idaroom.test','+213582340307' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شريبط عبد المعم','M','2010-03-21', id, 'student44438@idaroom.test','+213588461803' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شريط أشواق','F','2008-08-05', id, 'student66155@idaroom.test','+213588320463' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'علالوش أمير خليل','M','2010-03-02', id, 'student62350@idaroom.test','+213558586340' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عوار محمد تقي الدين','M','2009-03-17', id, 'student38746@idaroom.test','+213528566572' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'لكحل نزيم إسلام','M','2011-01-04', id, 'student76784@idaroom.test','+213576238574' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'مهني لميس رتاج','F','2008-08-21', id, 'student21915@idaroom.test','+213516323852' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عميور اسيل','F','2010-01-07', id, 'student24371@idaroom.test','+213530514014' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عابر محمد وسيم','M','2009-10-06', id, 'student92240@idaroom.test','+213531472420' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'نسمي باي ضياء عبد العزيز','F','2009-05-22', id, 'student99192@idaroom.test','+213566661351' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'وغليسي دعاء','F','2010-07-27', id, 'student88172@idaroom.test','+213518526544' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'لمداوي جاسمين أريج','F','2010-03-26', id, 'student60432@idaroom.test','+213561220073' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'إينوش نهال رقية','F','2009-02-06', id, 'student88104@idaroom.test','+213572820592' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'أحميدة محمد جابر','M','2010-02-20', id, 'student79352@idaroom.test','+213543744231' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'غريب سامي اياد','M','2009-04-03', id, 'student82512@idaroom.test','+213511540956' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'وادي محمد نضال','M','2010-11-22', id, 'student99166@idaroom.test','+213525374874' FROM public.classes WHERE name='ج م أ 1' LIMIT 1;
;
-- >>> 20260517080418_cf8a39bc-e7c4-413c-940c-1d4c78af9aac.sql
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_roles(uuid) FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, authenticated, anon;
;
-- >>> 20260518084150_6590432c-4f53-4cce-874b-6fb8a76dcda8.sql

-- RFID Cards table
CREATE TABLE public.rfid_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL UNIQUE,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'active',
  note TEXT,
  assigned_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.rfid_cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view cards"
ON public.rfid_cards FOR SELECT TO authenticated USING (true);

CREATE POLICY "Staff manage cards"
ON public.rfid_cards FOR ALL TO authenticated
USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));

CREATE TRIGGER trg_rfid_cards_updated
BEFORE UPDATE ON public.rfid_cards
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Card scans table
CREATE TABLE public.card_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  direction TEXT NOT NULL DEFAULT 'in',
  gate_id TEXT,
  scanned_by UUID,
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_card_scans_scanned_at ON public.card_scans(scanned_at DESC);
CREATE INDEX idx_card_scans_card_uid ON public.card_scans(card_uid);

ALTER TABLE public.card_scans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view scans"
ON public.card_scans FOR SELECT TO authenticated USING (true);

CREATE POLICY "Gate and staff can insert scans"
ON public.card_scans FOR INSERT TO authenticated
WITH CHECK (
  has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director')
  OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'gate_monitor')
);

CREATE POLICY "Staff manage scans"
ON public.card_scans FOR ALL TO authenticated
USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));

-- Realtime
ALTER TABLE public.rfid_cards REPLICA IDENTITY FULL;
ALTER TABLE public.card_scans REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rfid_cards;
ALTER PUBLICATION supabase_realtime ADD TABLE public.card_scans;

;
-- >>> 20260519113222_1aac4686-8c85-44b3-aa64-d454da19fa49.sql

-- Attendance sessions
CREATE TABLE public.attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_date DATE NOT NULL DEFAULT CURRENT_DATE,
  period TEXT,
  subject TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_att_sessions_class_date ON public.attendance_sessions(class_id, session_date DESC);

CREATE TRIGGER trg_att_sessions_updated_at
  BEFORE UPDATE ON public.attendance_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view sessions"
  ON public.attendance_sessions FOR SELECT TO authenticated USING (true);

CREATE POLICY "Staff can manage sessions"
  ON public.attendance_sessions FOR ALL TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'director') OR
    public.has_role(auth.uid(), 'supervisor') OR
    public.has_role(auth.uid(), 'teacher')
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'director') OR
    public.has_role(auth.uid(), 'supervisor') OR
    public.has_role(auth.uid(), 'teacher')
  );

-- Attendance records
CREATE TABLE public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present',
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, student_id),
  CHECK (status IN ('present','absent','late','excused'))
);
CREATE INDEX idx_att_records_student ON public.attendance_records(student_id);
CREATE INDEX idx_att_records_session ON public.attendance_records(session_id);

CREATE TRIGGER trg_att_records_updated_at
  BEFORE UPDATE ON public.attendance_records
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can view records"
  ON public.attendance_records FOR SELECT TO authenticated USING (true);

CREATE POLICY "Staff can manage records"
  ON public.attendance_records FOR ALL TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'director') OR
    public.has_role(auth.uid(), 'supervisor') OR
    public.has_role(auth.uid(), 'teacher')
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'director') OR
    public.has_role(auth.uid(), 'supervisor') OR
    public.has_role(auth.uid(), 'teacher')
  );

-- Notifications
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_label TEXT,
  title TEXT NOT NULL,
  body TEXT,
  channel TEXT NOT NULL DEFAULT 'inapp',
  status TEXT NOT NULL DEFAULT 'sent',
  related_student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  read_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (channel IN ('inapp','email','sms')),
  CHECK (status IN ('sent','simulated','failed','read'))
);
CREATE INDEX idx_notif_recipient ON public.notifications(recipient_id, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Recipient or staff can view"
  ON public.notifications FOR SELECT TO authenticated
  USING (
    recipient_id = auth.uid()
    OR public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
  );

CREATE POLICY "Staff can insert"
  ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'director') OR
    public.has_role(auth.uid(), 'supervisor') OR
    public.has_role(auth.uid(), 'teacher')
  );

CREATE POLICY "Recipient can mark read"
  ON public.notifications FOR UPDATE TO authenticated
  USING (recipient_id = auth.uid());

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

;
-- >>> 20260520140304_4262d0ae-1654-478e-ba81-4cf41f374681.sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _name text;
  _whitelisted_role app_role;
  _requested_role app_role;
  _requested_text text;
BEGIN
  _name := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email);
  INSERT INTO public.profiles (id, full_name, preferred_language)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'));

  SELECT role INTO _whitelisted_role FROM public.staff_whitelist
  WHERE full_name = _name LIMIT 1;

  _requested_text := NEW.raw_user_meta_data->>'requested_role';
  IF _requested_text IS NOT NULL AND _requested_text <> '' THEN
    BEGIN
      _requested_role := _requested_text::app_role;
    EXCEPTION WHEN others THEN
      _requested_role := NULL;
    END;
  END IF;

  IF _whitelisted_role IS NOT NULL THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, _whitelisted_role);
  ELSIF _requested_role IS NOT NULL THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, _requested_role);
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'student');
  END IF;

  UPDATE public.students SET user_id = NEW.id WHERE full_name = _name AND user_id IS NULL;

  RETURN NEW;
END;
$function$;
;
-- >>> 20260520141446_31cfd953-4215-483f-b89f-cf4f8cfaf957.sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _name text;
  _whitelisted_role app_role;
  _requested_role app_role;
  _requested_text text;
BEGIN
  _name := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
    NULLIF(NEW.raw_user_meta_data->>'name', ''),
    NEW.email
  );

  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (
    NEW.id,
    _name,
    COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'),
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  SELECT role INTO _whitelisted_role
  FROM public.staff_whitelist
  WHERE full_name = _name
  LIMIT 1;

  _requested_text := NEW.raw_user_meta_data->>'requested_role';
  IF _requested_text IS NOT NULL AND _requested_text <> '' THEN
    BEGIN
      _requested_role := _requested_text::app_role;
    EXCEPTION WHEN others THEN
      _requested_role := NULL;
    END;
  END IF;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, COALESCE(_whitelisted_role, _requested_role, 'student'::app_role))
  ON CONFLICT (user_id, role) DO NOTHING;

  UPDATE public.students
  SET user_id = NEW.id
  WHERE full_name = _name AND user_id IS NULL;

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'on_auth_user_created'
  ) THEN
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.ensure_user_roles(_requested_role app_role DEFAULT NULL)
RETURNS SETOF app_role
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _user_id uuid;
  _email text;
  _name text;
  _avatar text;
  _role app_role;
BEGIN
  _user_id := auth.uid();
  IF _user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT
    u.email,
    COALESCE(NULLIF(u.raw_user_meta_data->>'full_name', ''), NULLIF(u.raw_user_meta_data->>'name', ''), u.email),
    u.raw_user_meta_data->>'avatar_url'
  INTO _email, _name, _avatar
  FROM auth.users u
  WHERE u.id = _user_id;

  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (_user_id, _name, 'ar', _avatar)
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
    avatar_url = COALESCE(public.profiles.avatar_url, EXCLUDED.avatar_url),
    updated_at = now();

  IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id) THEN
    IF _requested_role IS NOT NULL THEN
      _role := _requested_role;
    ELSIF lower(_email) IN ('boukaachey@gmail.com', 'boukaacheyounes@gmail.com') THEN
      _role := 'admin'::app_role;
    ELSE
      _role := 'student'::app_role;
    END IF;

    INSERT INTO public.user_roles (user_id, role)
    VALUES (_user_id, _role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  IF lower(_email) IN ('boukaachey@gmail.com', 'boukaacheyounes@gmail.com') THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES
      (_user_id, 'admin'::app_role),
      (_user_id, 'director'::app_role),
      (_user_id, 'supervisor'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN QUERY
  SELECT ur.role
  FROM public.user_roles ur
  WHERE ur.user_id = _user_id
  ORDER BY CASE ur.role
    WHEN 'admin' THEN 1
    WHEN 'director' THEN 2
    WHEN 'supervisor' THEN 3
    WHEN 'teacher' THEN 4
    WHEN 'gate_monitor' THEN 5
    WHEN 'parent' THEN 6
    WHEN 'student' THEN 7
    ELSE 99
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_user_roles(app_role) TO authenticated;

INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
SELECT
  u.id,
  COALESCE(NULLIF(u.raw_user_meta_data->>'full_name', ''), NULLIF(u.raw_user_meta_data->>'name', ''), u.email),
  COALESCE(u.raw_user_meta_data->>'preferred_language', 'ar'),
  u.raw_user_meta_data->>'avatar_url'
FROM auth.users u
WHERE lower(u.email) IN ('boukaachey@gmail.com', 'boukaacheyounes@gmail.com')
ON CONFLICT (id) DO UPDATE SET
  full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
  avatar_url = COALESCE(public.profiles.avatar_url, EXCLUDED.avatar_url),
  updated_at = now();

INSERT INTO public.user_roles (user_id, role)
SELECT u.id, r.role::app_role
FROM auth.users u
CROSS JOIN (VALUES ('admin'), ('director'), ('supervisor')) AS r(role)
WHERE lower(u.email) IN ('boukaachey@gmail.com', 'boukaacheyounes@gmail.com')
ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO public.user_roles (user_id, role)
SELECT u.id, 'student'::app_role
FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_roles ur WHERE ur.user_id = u.id
)
ON CONFLICT (user_id, role) DO NOTHING;
;
-- >>> 20260520141511_c27683fc-0718-43f3-b779-565c04e59ee3.sql
DROP FUNCTION IF EXISTS public.ensure_user_roles(app_role);

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'Users can create own profile during test'
  ) THEN
    CREATE POLICY "Users can create own profile during test"
    ON public.profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_roles'
      AND policyname = 'Users can create own role during test'
  ) THEN
    CREATE POLICY "Users can create own role during test"
    ON public.user_roles
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

INSERT INTO public.user_roles (user_id, role)
SELECT u.id, r.role::app_role
FROM auth.users u
CROSS JOIN (VALUES ('admin'), ('director'), ('supervisor')) AS r(role)
WHERE lower(u.email) IN ('boukaachey@gmail.com', 'boukaacheyounes@gmail.com')
ON CONFLICT (user_id, role) DO NOTHING;
;
-- >>> 20260520141811_102618ef-3ff7-4f7d-aca5-343b7734e349.sql
CREATE TABLE IF NOT EXISTS public.school_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  decision_type text NOT NULL DEFAULT 'announcement',
  body text,
  status text NOT NULL DEFAULT 'active',
  starts_at timestamptz DEFAULT now(),
  ends_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.behavior_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE,
  record_type text NOT NULL DEFAULT 'positive',
  points integer NOT NULL DEFAULT 0,
  title text NOT NULL,
  note text,
  recorded_by uuid,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.library_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  author text,
  item_type text NOT NULL DEFAULT 'book',
  total_copies integer NOT NULL DEFAULT 1,
  available_copies integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.library_loans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid REFERENCES public.library_items(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  loaned_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz,
  returned_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.school_trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  destination text,
  trip_date date,
  status text NOT NULL DEFAULT 'planned',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.trip_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid REFERENCES public.school_trips(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  consent_status text NOT NULL DEFAULT 'pending',
  attended boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trip_id, student_id)
);

CREATE TABLE IF NOT EXISTS public.exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  subject text NOT NULL,
  exam_date date,
  room text,
  status text NOT NULL DEFAULT 'scheduled',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['school_decisions','behavior_records','library_items','library_loans','school_trips','trip_participants','exams']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
  END LOOP;
END $$;

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['school_decisions','behavior_records','library_items','library_loans','school_trips','trip_participants','exams']
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=tbl AND policyname='Authenticated can view school admin data') THEN
      EXECUTE format('CREATE POLICY "Authenticated can view school admin data" ON public.%I FOR SELECT TO authenticated USING (true)', tbl);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=tbl AND policyname='Management can change school admin data') THEN
      EXECUTE format('CREATE POLICY "Management can change school admin data" ON public.%I FOR ALL TO authenticated USING (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor'')) WITH CHECK (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor''))', tbl);
    END IF;
  END LOOP;
END $$;

DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['school_decisions','behavior_records','library_items','library_loans','school_trips','trip_participants','exams']
  LOOP
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_' || tbl || '_updated_at') THEN
      CONTINUE;
    END IF;
    IF tbl <> 'trip_participants' THEN
      EXECUTE format('CREATE TRIGGER set_%I_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', tbl, tbl);
    END IF;
  END LOOP;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE public.school_decisions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.behavior_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_loans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.school_trips;
ALTER PUBLICATION supabase_realtime ADD TABLE public.trip_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.exams;

INSERT INTO public.library_items (title, author, item_type, total_copies, available_copies)
VALUES
  ('كتاب الرياضيات — سنة رابعة متوسط', 'وزارة التربية', 'book', 20, 20),
  ('كتاب اللغة العربية — سنة أولى ثانوي', 'وزارة التربية', 'book', 18, 18)
ON CONFLICT DO NOTHING;

INSERT INTO public.school_decisions (title, decision_type, body, status)
VALUES ('اجتماع إداري تجريبي', 'announcement', 'قرار تجريبي للتأكد من عمل صفحة الإدارة والتحديث الفوري.', 'active')
ON CONFLICT DO NOTHING;
;
-- >>> 20260520142115_051126cd-b5da-4b0e-b0ef-bd4d6febfb74.sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
;
-- >>> 20260523120200_36d6559b-fe82-4781-b9eb-f8e5d78c8226.sql
-- Roles enum
CREATE TYPE public.app_role AS ENUM ('admin', 'director', 'supervisor', 'teacher', 'parent', 'student', 'gate_monitor');

-- Profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  preferred_language TEXT DEFAULT 'ar',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id UUID)
RETURNS SETOF app_role LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.user_roles WHERE user_id = _user_id
$$;

CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));
CREATE POLICY "Users can create own profile during test" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can manage all roles" ON public.user_roles FOR ALL USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Users can create own role during test" ON public.user_roles FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(UUID, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_roles(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(UUID, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_roles(UUID) TO authenticated;

-- Classes
CREATE TABLE public.classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  level text,
  branch text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone authenticated can view classes" ON public.classes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage classes" ON public.classes FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'));

-- Students
CREATE TABLE public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  gender text CHECK (gender IN ('M','F')),
  date_of_birth date,
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  fake_email text,
  fake_phone text,
  user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_students_class ON public.students(class_id);
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view students" ON public.students FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff manage students" ON public.students FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Staff whitelist
CREATE TABLE public.staff_whitelist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL UNIQUE,
  role app_role NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.staff_whitelist ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage staff whitelist" ON public.staff_whitelist FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- RFID Cards
CREATE TABLE public.rfid_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL UNIQUE,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'active',
  note TEXT,
  assigned_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.rfid_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view cards" ON public.rfid_cards FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff manage cards" ON public.rfid_cards FOR ALL TO authenticated
USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_rfid_cards_updated BEFORE UPDATE ON public.rfid_cards
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Card scans
CREATE TABLE public.card_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  direction TEXT NOT NULL DEFAULT 'in',
  gate_id TEXT,
  scanned_by UUID,
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_card_scans_scanned_at ON public.card_scans(scanned_at DESC);
CREATE INDEX idx_card_scans_card_uid ON public.card_scans(card_uid);
ALTER TABLE public.card_scans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view scans" ON public.card_scans FOR SELECT TO authenticated USING (true);
CREATE POLICY "Gate and staff can insert scans" ON public.card_scans FOR INSERT TO authenticated
WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'gate_monitor'));
CREATE POLICY "Staff manage scans" ON public.card_scans FOR ALL TO authenticated
USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));

-- Attendance
CREATE TABLE public.attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_date DATE NOT NULL DEFAULT CURRENT_DATE,
  period TEXT,
  subject TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_att_sessions_class_date ON public.attendance_sessions(class_id, session_date DESC);
CREATE TRIGGER trg_att_sessions_updated_at BEFORE UPDATE ON public.attendance_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view sessions" ON public.attendance_sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can manage sessions" ON public.attendance_sessions FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));

CREATE TABLE public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present',
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, student_id),
  CHECK (status IN ('present','absent','late','excused'))
);
CREATE INDEX idx_att_records_student ON public.attendance_records(student_id);
CREATE INDEX idx_att_records_session ON public.attendance_records(session_id);
CREATE TRIGGER trg_att_records_updated_at BEFORE UPDATE ON public.attendance_records
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view records" ON public.attendance_records FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can manage records" ON public.attendance_records FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));

-- Notifications
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_label TEXT,
  title TEXT NOT NULL,
  body TEXT,
  channel TEXT NOT NULL DEFAULT 'inapp',
  status TEXT NOT NULL DEFAULT 'sent',
  related_student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  read_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (channel IN ('inapp','email','sms')),
  CHECK (status IN ('sent','simulated','failed','read'))
);
CREATE INDEX idx_notif_recipient ON public.notifications(recipient_id, created_at DESC);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Recipient or staff can view" ON public.notifications FOR SELECT TO authenticated
  USING (recipient_id = auth.uid() OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE POLICY "Staff can insert" ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
CREATE POLICY "Recipient can mark read" ON public.notifications FOR UPDATE TO authenticated USING (recipient_id = auth.uid());

-- Admin/behavior/library/trips/exams
CREATE TABLE public.school_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  decision_type text NOT NULL DEFAULT 'announcement',
  body text,
  status text NOT NULL DEFAULT 'active',
  starts_at timestamptz DEFAULT now(),
  ends_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.behavior_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE,
  record_type text NOT NULL DEFAULT 'positive',
  points integer NOT NULL DEFAULT 0,
  title text NOT NULL,
  note text,
  recorded_by uuid,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.library_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  author text,
  item_type text NOT NULL DEFAULT 'book',
  total_copies integer NOT NULL DEFAULT 1,
  available_copies integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.library_loans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid REFERENCES public.library_items(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  loaned_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz,
  returned_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.school_trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  destination text,
  trip_date date,
  status text NOT NULL DEFAULT 'planned',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.trip_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid REFERENCES public.school_trips(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  consent_status text NOT NULL DEFAULT 'pending',
  attended boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trip_id, student_id)
);
CREATE TABLE public.exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  subject text NOT NULL,
  exam_date date,
  room text,
  status text NOT NULL DEFAULT 'scheduled',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['school_decisions','behavior_records','library_items','library_loans','school_trips','trip_participants','exams']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
    EXECUTE format('CREATE POLICY "Authenticated can view school admin data" ON public.%I FOR SELECT TO authenticated USING (true)', tbl);
    EXECUTE format('CREATE POLICY "Management can change school admin data" ON public.%I FOR ALL TO authenticated USING (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor'')) WITH CHECK (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor''))', tbl);
    IF tbl <> 'trip_participants' THEN
      EXECUTE format('CREATE TRIGGER set_%I_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', tbl, tbl);
    END IF;
  END LOOP;
END $$;

-- Realtime
ALTER TABLE public.classes REPLICA IDENTITY FULL;
ALTER TABLE public.students REPLICA IDENTITY FULL;
ALTER TABLE public.rfid_cards REPLICA IDENTITY FULL;
ALTER TABLE public.card_scans REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.classes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.students;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rfid_cards;
ALTER PUBLICATION supabase_realtime ADD TABLE public.card_scans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.school_decisions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.behavior_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_loans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.school_trips;
ALTER PUBLICATION supabase_realtime ADD TABLE public.trip_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.exams;

-- Whitelist
INSERT INTO public.staff_whitelist (full_name, role, note)
VALUES ('بوكعاش يونس إدريس', 'admin', 'مسؤول رئيسي')
ON CONFLICT (full_name) DO UPDATE SET role = EXCLUDED.role;

-- Seed classes
INSERT INTO public.classes (name, level, branch) VALUES ('ج م ع ت 4', '1AS', 'جذع مشترك علوم وتكنولوجيا');
INSERT INTO public.classes (name, level, branch) VALUES ('ج م أ 1', '1AS', 'جذع مشترك آداب');

-- Seed students class 1
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ابن خرورو عبد الرحمان','M','2009-11-05', id, 'student93810@idaroom.test','+213524942603' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ابن مناح أروى','F','2010-11-03', id, 'student13278@idaroom.test','+213546913810' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن جامع أريج نور الهدى','F','2010-12-01', id, 'student42098@idaroom.test','+213539958838' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن سماعين بلال','M','2010-08-13', id, 'student28289@idaroom.test','+213523756669' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن عامر رنيم','F','2010-06-21', id, 'student98696@idaroom.test','+213583197857' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن قدواد ندى حبيبة','F','2010-09-14', id, 'student21395@idaroom.test','+213589254563' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوزيتونة ليله','F','2011-03-23', id, 'student65302@idaroom.test','+213514265799' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوعبيد ملاك','F','2010-01-05', id, 'student13905@idaroom.test','+213522575562' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوعصيدة أمينة','F','2010-04-10', id, 'student38657@idaroom.test','+213541227216' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوكعاش يونس إدريس','M','2011-03-07', id, 'student76237@idaroom.test','+213590801586' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'حركاتي محمد الصالح','M','2009-05-06', id, 'student13478@idaroom.test','+213585329037' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'حيرش محمد تميم','M','2010-11-04', id, 'student36062@idaroom.test','+213597226012' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'خناوي ألاء الرحمان','F','2010-06-07', id, 'student81426@idaroom.test','+213566306997' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'خيري نسرين','F','2011-01-19', id, 'student38893@idaroom.test','+213570291817' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سوالمية محمد الصالح','M','2009-04-06', id, 'student87236@idaroom.test','+213547338124' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شكارلي محمد بهاء الدين','M','2010-09-11', id, 'student10851@idaroom.test','+213531429110' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شوابية قصي','M','2010-10-21', id, 'student65392@idaroom.test','+213555667651' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عباس حداد فزيل مولود','M','2010-06-15', id, 'student46421@idaroom.test','+213530868105' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عبد الرزاق يوسف','M','2010-07-06', id, 'student38221@idaroom.test','+213555176955' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عمرو عياش أنفال','F','2011-01-24', id, 'student23396@idaroom.test','+213522448136' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'فاضل اياد شمس الدين','M','2010-07-30', id, 'student59797@idaroom.test','+213522981052' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قادة أمنية','F','2010-07-05', id, 'student57052@idaroom.test','+213556164955' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قجال رائد نزار','M','2010-01-10', id, 'student89131@idaroom.test','+213545503389' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قروي جهينة أناييس','F','2010-06-09', id, 'student15695@idaroom.test','+213571662963' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قليل نور مايا','F','2010-10-09', id, 'student80284@idaroom.test','+213526753883' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'كحول زكريا','M','2010-05-27', id, 'student59615@idaroom.test','+213520576383' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'كحول يحي','M','2010-05-27', id, 'student82357@idaroom.test','+213549349722' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'لعور نريمان','F','2010-03-18', id, 'student92397@idaroom.test','+213593016315' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'منتوري نادر','M','2010-01-18', id, 'student57400@idaroom.test','+213587490893' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ميمون عبد الله','M','2010-09-19', id, 'student35203@idaroom.test','+213519335534' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'ميمون نجيب','M','2009-06-07', id, 'student16006@idaroom.test','+213598753260' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'يخلف إياد عبد الرحيم','M','2010-08-12', id, 'student39871@idaroom.test','+213548840994' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'تواتي إيناس','F','2010-01-01', id, 'student20458@idaroom.test','+213541244663' FROM public.classes WHERE name='ج م ع ت 4';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'قدوري إيناس','F','2010-01-01', id, 'student23238@idaroom.test','+213561019678' FROM public.classes WHERE name='ج م ع ت 4';

-- Seed students class 2
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'الخزعلي علي','M','2010-11-16', id, 'student56566@idaroom.test','+213538119557' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن جامع عبدالرحمان','M','2009-03-19', id, 'student97841@idaroom.test','+213545833156' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن فضة اسيل ندي الريحان','F','2011-01-30', id, 'student99593@idaroom.test','+213596977837' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بن فيسح عائشة','F','2011-03-05', id, 'student19358@idaroom.test','+213591756179' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوخالفة رامي','M','2010-11-10', id, 'student93227@idaroom.test','+213532969840' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوخالفة هارون الرشيد','M','2009-10-17', id, 'student80010@idaroom.test','+213542857966' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بودرياسي إبراهيم خليل','M','2009-09-29', id, 'student31417@idaroom.test','+213572043515' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بودفة زينب','F','2007-05-17', id, 'student59735@idaroom.test','+213546231783' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوسالم رنا مرام','F','2010-09-03', id, 'student93886@idaroom.test','+213584752529' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوشيلاون محمد وليد','M','2010-11-27', id, 'student38785@idaroom.test','+213553524491' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوكرو حمزة','M','2010-03-19', id, 'student17331@idaroom.test','+213540742311' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'بوهيدل سراج الدين','M','2010-04-08', id, 'student14207@idaroom.test','+213552339391' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'جبلية رقية لجين','F','2010-01-03', id, 'student62581@idaroom.test','+213545935572' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'جلواط سامي شعيب','M','2009-06-24', id, 'student18675@idaroom.test','+213538317637' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'خنفوسي محمد فراس','M','2010-04-25', id, 'student84341@idaroom.test','+213552235350' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'دالي ريم','F','2011-02-03', id, 'student37869@idaroom.test','+213597971488' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'دحدوح شعيب','M','2008-09-15', id, 'student75435@idaroom.test','+213563100814' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'رزاق اية','F','2010-07-22', id, 'student94259@idaroom.test','+213571586053' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سبيح دينا نورهان','F','2008-08-03', id, 'student28726@idaroom.test','+213545551614' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سوفي عبد المعز','M','2009-06-02', id, 'student28301@idaroom.test','+213543101783' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'سيابة شيماء شروق','F','2010-07-05', id, 'student83579@idaroom.test','+213582340307' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شريبط عبد المعم','M','2010-03-21', id, 'student44438@idaroom.test','+213588461803' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'شريط أشواق','F','2008-08-05', id, 'student66155@idaroom.test','+213588320463' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'علالوش أمير خليل','M','2010-03-02', id, 'student62350@idaroom.test','+213558586340' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عوار محمد تقي الدين','M','2009-03-17', id, 'student38746@idaroom.test','+213528566572' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'لكحل نزيم إسلام','M','2011-01-04', id, 'student76784@idaroom.test','+213576238574' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'مهني لميس رتاج','F','2008-08-21', id, 'student21915@idaroom.test','+213516323852' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عميور اسيل','F','2010-01-07', id, 'student24371@idaroom.test','+213530514014' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'عابر محمد وسيم','M','2009-10-06', id, 'student92240@idaroom.test','+213531472420' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'نسمي باي ضياء عبد العزيز','F','2009-05-22', id, 'student99192@idaroom.test','+213566661351' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'وغليسي دعاء','F','2010-07-27', id, 'student88172@idaroom.test','+213518526544' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'لمداوي جاسمين أريج','F','2010-03-26', id, 'student60432@idaroom.test','+213561220073' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'إينوش نهال رقية','F','2009-02-06', id, 'student88104@idaroom.test','+213572820592' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'أحميدة محمد جابر','M','2010-02-20', id, 'student79352@idaroom.test','+213543744231' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'غريب سامي اياد','M','2009-04-03', id, 'student82512@idaroom.test','+213511540956' FROM public.classes WHERE name='ج م أ 1';
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone) SELECT 'وادي محمد نضال','M','2010-11-22', id, 'student99166@idaroom.test','+213525374874' FROM public.classes WHERE name='ج م أ 1';

-- Auto-elevate boukaachey on signup via trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _name text;
  _email text;
  _whitelisted_role app_role;
  _requested_role app_role;
  _requested_text text;
BEGIN
  _email := lower(NEW.email);
  _name := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NEW.email
  );

  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'), NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  IF _email IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com') THEN
    INSERT INTO public.user_roles (user_id, role) VALUES
      (NEW.id, 'admin'::app_role),
      (NEW.id, 'director'::app_role),
      (NEW.id, 'supervisor'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    SELECT role INTO _whitelisted_role FROM public.staff_whitelist WHERE full_name = _name LIMIT 1;
    _requested_text := NEW.raw_user_meta_data->>'requested_role';
    IF _requested_text IS NOT NULL AND _requested_text <> '' THEN
      BEGIN _requested_role := _requested_text::app_role;
      EXCEPTION WHEN others THEN _requested_role := NULL; END;
    END IF;
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, COALESCE(_whitelisted_role, _requested_role, 'student'::app_role))
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  UPDATE public.students SET user_id = NEW.id WHERE full_name = _name AND user_id IS NULL;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- If boukaachey already signed up before this migration, promote now
INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
SELECT u.id,
  COALESCE(NULLIF(u.raw_user_meta_data->>'full_name',''), NULLIF(u.raw_user_meta_data->>'name',''), u.email),
  'ar', u.raw_user_meta_data->>'avatar_url'
FROM auth.users u
WHERE lower(u.email) IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.user_roles (user_id, role)
SELECT u.id, r.role::app_role
FROM auth.users u
CROSS JOIN (VALUES ('admin'),('director'),('supervisor')) AS r(role)
WHERE lower(u.email) IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com')
ON CONFLICT (user_id, role) DO NOTHING;

-- Seed admin demo content
INSERT INTO public.library_items (title, author, item_type, total_copies, available_copies) VALUES
  ('كتاب الرياضيات — سنة رابعة متوسط','وزارة التربية','book',20,20),
  ('كتاب اللغة العربية — سنة أولى ثانوي','وزارة التربية','book',18,18);

INSERT INTO public.school_decisions (title, decision_type, body, status)
VALUES ('اجتماع إداري تجريبي','announcement','قرار تجريبي للتأكد من عمل صفحة الإدارة والتحديث الفوري.','active');
;
-- >>> 20260523120216_66be1a92-5e1d-4e64-b6cd-5ced3d69f277.sql
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_roles(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_roles(uuid) TO authenticated;
;
-- >>> 20260524093053_5034412f-04a3-475d-8f45-a0890acd0d7f.sql

CREATE INDEX IF NOT EXISTS idx_card_scans_scanned_at ON public.card_scans (scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_card_scans_card_uid ON public.card_scans (card_uid);
CREATE INDEX IF NOT EXISTS idx_attendance_records_student_id ON public.attendance_records (student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_created_at ON public.attendance_records (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rfid_cards_card_uid ON public.rfid_cards (card_uid);
CREATE INDEX IF NOT EXISTS idx_rfid_cards_student_id ON public.rfid_cards (student_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_school_decisions_status_starts_at ON public.school_decisions (status, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_students_user_id ON public.students (user_id);
CREATE INDEX IF NOT EXISTS idx_students_class_id ON public.students (class_id);

CREATE OR REPLACE FUNCTION public.get_overview_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'students', (SELECT count(*) FROM public.students),
    'cards', (SELECT count(*) FROM public.rfid_cards),
    'attendance', (SELECT count(*) FROM public.attendance_records),
    'notifications', (SELECT count(*) FROM public.notifications),
    'classes', (SELECT count(*) FROM public.classes),
    'scans', (SELECT count(*) FROM public.card_scans)
  )
$$;

GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated, anon;

;
-- >>> 20260524093104_497dfe52-5edf-4683-96c4-3b837cf3053a.sql

REVOKE EXECUTE ON FUNCTION public.get_overview_stats() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated;

;
-- >>> 20260525152524_2565f0f0-3080-4314-a046-576a4ba3b44c.sql

-- 1. Fix profiles: scope to authenticated only
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));

CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT TO authenticated USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (auth.uid() = id);

-- 2. Lock down user_roles: remove self-INSERT
DROP POLICY IF EXISTS "Users can create own role during test" ON public.user_roles;
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can manage all roles" ON public.user_roles;

CREATE POLICY "Users can view own roles" ON public.user_roles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all roles" ON public.user_roles
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- 3. Ensure new-user trigger is attached (assigns roles server-side)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 4. Students: restrict reads to staff, parents (own children link N/A), students (self)
DROP POLICY IF EXISTS "Authenticated can view students" ON public.students;
CREATE POLICY "Staff or self can view students" ON public.students
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR public.has_role(auth.uid(), 'gate_monitor')
    OR user_id = auth.uid()
  );

-- 5. rfid_cards: staff + gate monitor + self
DROP POLICY IF EXISTS "Authenticated can view cards" ON public.rfid_cards;
CREATE POLICY "Staff can view cards" ON public.rfid_cards
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'gate_monitor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = rfid_cards.student_id AND s.user_id = auth.uid())
  );

-- 6. card_scans: staff + gate monitor + self
DROP POLICY IF EXISTS "Authenticated can view scans" ON public.card_scans;
CREATE POLICY "Staff can view scans" ON public.card_scans
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'gate_monitor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = card_scans.student_id AND s.user_id = auth.uid())
  );

-- 7. behavior_records: staff only + self
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.behavior_records;
CREATE POLICY "Staff can view behavior" ON public.behavior_records
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = behavior_records.student_id AND s.user_id = auth.uid())
  );

-- 8. attendance_records: staff + self
DROP POLICY IF EXISTS "Authenticated can view records" ON public.attendance_records;
CREATE POLICY "Staff or self can view attendance" ON public.attendance_records
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = attendance_records.student_id AND s.user_id = auth.uid())
  );

-- 9. library_loans: staff + self
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.library_loans;
CREATE POLICY "Staff or self can view loans" ON public.library_loans
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = library_loans.student_id AND s.user_id = auth.uid())
  );

-- 10. trip_participants: staff + self
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.trip_participants;
CREATE POLICY "Staff or self can view trip participants" ON public.trip_participants
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = trip_participants.student_id AND s.user_id = auth.uid())
  );

-- 11. Revoke get_overview_stats from anon
REVOKE EXECUTE ON FUNCTION public.get_overview_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated;

-- 12. Realtime: restrict subscriptions to authenticated staff
ALTER TABLE IF EXISTS realtime.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff can subscribe to realtime" ON realtime.messages;
CREATE POLICY "Staff can subscribe to realtime" ON realtime.messages
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR public.has_role(auth.uid(), 'gate_monitor')
  );

;
-- >>> 20260525155128_e23cbfb6-7771-4b1b-8a5d-b58dddb3f870.sql

ALTER TABLE public.card_scans
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS note text,
  ADD COLUMN IF NOT EXISTS visitor_name text;

CREATE INDEX IF NOT EXISTS idx_card_scans_mode ON public.card_scans(mode);
CREATE INDEX IF NOT EXISTS idx_card_scans_student_scanned_at ON public.card_scans(student_id, scanned_at DESC);

;
-- >>> 20260527135654_cde0433b-f69c-42d2-90ba-317d832fdc24.sql
-- Fix 1: Remove privilege escalation via requested_role in signup metadata
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _name text;
  _email text;
  _whitelisted_role app_role;
BEGIN
  _email := lower(NEW.email);
  _name := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NEW.email
  );

  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'), NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  IF _email IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com') THEN
    INSERT INTO public.user_roles (user_id, role) VALUES
      (NEW.id, 'admin'::app_role),
      (NEW.id, 'director'::app_role),
      (NEW.id, 'supervisor'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    -- Role elevation only through staff_whitelist (server-controlled) or admin action.
    -- Never trust requested_role from client-supplied raw_user_meta_data.
    SELECT role INTO _whitelisted_role FROM public.staff_whitelist WHERE full_name = _name LIMIT 1;
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, COALESCE(_whitelisted_role, 'student'::app_role))
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  UPDATE public.students SET user_id = NEW.id WHERE full_name = _name AND user_id IS NULL;

  RETURN NEW;
END;
$function$;

-- Fix 2: Restrict teacher visibility of students to only those in classes they teach
DROP POLICY IF EXISTS "Staff or self can view students" ON public.students;
CREATE POLICY "Staff or self can view students"
ON public.students
FOR SELECT
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'director'::app_role)
  OR has_role(auth.uid(), 'supervisor'::app_role)
  OR has_role(auth.uid(), 'gate_monitor'::app_role)
  OR (user_id = auth.uid())
  OR (
    has_role(auth.uid(), 'teacher'::app_role)
    AND EXISTS (
      SELECT 1 FROM public.attendance_sessions s
      WHERE s.teacher_id = auth.uid() AND s.class_id = students.class_id
    )
  )
);

-- Fix 3: Restrict teacher visibility of attendance to their own sessions
DROP POLICY IF EXISTS "Staff or self can view attendance" ON public.attendance_records;
CREATE POLICY "Staff or self can view attendance"
ON public.attendance_records
FOR SELECT
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'director'::app_role)
  OR has_role(auth.uid(), 'supervisor'::app_role)
  OR (
    has_role(auth.uid(), 'teacher'::app_role)
    AND EXISTS (
      SELECT 1 FROM public.attendance_sessions s
      WHERE s.id = attendance_records.session_id AND s.teacher_id = auth.uid()
    )
  )
  OR EXISTS (
    SELECT 1 FROM public.students s
    WHERE s.id = attendance_records.student_id AND s.user_id = auth.uid()
  )
);
;
-- >>> 20260527135912_353ef4e0-6d5c-4acb-9d04-f03ac744757e.sql
ALTER TABLE public.attendance_records
  ADD COLUMN IF NOT EXISTS justified_at timestamptz,
  ADD COLUMN IF NOT EXISTS justified_by uuid,
  ADD COLUMN IF NOT EXISTS justification_note text;

CREATE OR REPLACE FUNCTION public.prevent_late_override()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Only constrain transitions out of 'late'
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'late'
     AND NEW.status <> 'late'
     AND OLD.justified_at IS NULL
     AND NEW.justified_at IS NULL THEN
    RAISE EXCEPTION 'LATE_NOT_JUSTIFIED: لا يمكن تعديل حالة الطالب من "متأخر" قبل تبرير التأخر.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_late_override ON public.attendance_records;
CREATE TRIGGER trg_prevent_late_override
BEFORE UPDATE ON public.attendance_records
FOR EACH ROW EXECUTE FUNCTION public.prevent_late_override();
;
-- >>> 20260610172322_ab0b9c03-13ed-4ffd-82bf-a474b8d37acf.sql

-- 1. Add email-based whitelist column (immutable identifier)
ALTER TABLE public.staff_whitelist ADD COLUMN IF NOT EXISTS email text;
CREATE UNIQUE INDEX IF NOT EXISTS staff_whitelist_email_key ON public.staff_whitelist (lower(email)) WHERE email IS NOT NULL;

-- 2. Rewrite handle_new_user to:
--    - Match staff_whitelist by email (not user-supplied name)
--    - Remove auto-link of students by name (admins must link explicitly)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _name text;
  _email text;
  _whitelisted_role app_role;
BEGIN
  _email := lower(NEW.email);
  _name := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NEW.email
  );

  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'), NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  IF _email IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com') THEN
    INSERT INTO public.user_roles (user_id, role) VALUES
      (NEW.id, 'admin'::app_role),
      (NEW.id, 'director'::app_role),
      (NEW.id, 'supervisor'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    -- Role elevation only via staff_whitelist matched on EMAIL (immutable, not spoofable).
    -- Names from raw_user_meta_data are attacker-controlled and MUST NOT grant roles.
    SELECT role INTO _whitelisted_role
      FROM public.staff_whitelist
      WHERE email IS NOT NULL AND lower(email) = _email
      LIMIT 1;
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, COALESCE(_whitelisted_role, 'student'::app_role))
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  -- Student linkage is no longer automatic by name — admins must link explicitly
  -- (e.g. via fake_email) to prevent account hijacking by display-name spoofing.

  RETURN NEW;
END;
$function$;

-- 3. Tighten realtime.messages subscription policy.
--    Previously: any staff role could subscribe to ALL topics, leaking PII
--    (date_of_birth, fake_email, fake_phone, behavior, attendance) to
--    teachers and gate_monitors beyond what their RLS SELECT permits.
--    Now: admin/director/supervisor get full access; teachers and
--    gate_monitors are scoped to topics relevant to their role.
DROP POLICY IF EXISTS "Staff can subscribe to realtime" ON realtime.messages;

CREATE POLICY "Realtime scoped by role"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
    OR (
      public.has_role(auth.uid(), 'teacher'::app_role)
      AND realtime.topic() ~ '^(attendance|behavior|exams|notifications|classes|students)(:|$)'
    )
    OR (
      public.has_role(auth.uid(), 'gate_monitor'::app_role)
      AND realtime.topic() ~ '^(card_scans|rfid_cards|notifications|gate)(:|$)'
    )
  );

;
-- >>> 20260610173913_5d71207f-3197-440e-b73b-669c0492c256.sql

CREATE TABLE IF NOT EXISTS public.parent_student (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  relation text DEFAULT 'parent',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (parent_user_id, student_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.parent_student TO authenticated;
GRANT ALL ON public.parent_student TO service_role;

ALTER TABLE public.parent_student ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Parents see own links"
  ON public.parent_student FOR SELECT TO authenticated
  USING (
    parent_user_id = auth.uid()
    OR public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
  );

CREATE POLICY "Staff manage parent links"
  ON public.parent_student FOR ALL TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
  );

CREATE INDEX IF NOT EXISTS idx_parent_student_parent ON public.parent_student(parent_user_id);
CREATE INDEX IF NOT EXISTS idx_parent_student_student ON public.parent_student(student_id);

-- Performance indexes for hot lookups
CREATE INDEX IF NOT EXISTS idx_card_scans_scanned_at ON public.card_scans(scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_card_scans_student ON public.card_scans(student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_student ON public.attendance_records(student_id);
CREATE INDEX IF NOT EXISTS idx_behavior_records_student ON public.behavior_records(student_id);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications(recipient_id);

;
-- >>> 20260615130523_2e2b523d-d242-4790-9058-b968ab45a465.sql

-- Grades table for exam results entry
CREATE TABLE public.grades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_id uuid NOT NULL REFERENCES public.exams(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  score numeric(5,2),
  max_score numeric(5,2) NOT NULL DEFAULT 20,
  remark text,
  entered_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (exam_id, student_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.grades TO authenticated;
GRANT ALL ON public.grades TO service_role;

ALTER TABLE public.grades ENABLE ROW LEVEL SECURITY;

-- Staff (admin, director, supervisor, teacher) can manage grades
CREATE POLICY "Staff manage grades"
  ON public.grades
  FOR ALL
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
    OR public.has_role(auth.uid(), 'teacher'::app_role)
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
    OR public.has_role(auth.uid(), 'teacher'::app_role)
  );

-- Students see their own grades
CREATE POLICY "Students see own grades"
  ON public.grades
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.students s
      WHERE s.id = grades.student_id
        AND s.user_id = auth.uid()
    )
  );

-- Parents see their linked children's grades
CREATE POLICY "Parents see linked children grades"
  ON public.grades
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_student ps
      WHERE ps.student_id = grades.student_id
        AND ps.parent_user_id = auth.uid()
    )
  );

CREATE INDEX idx_grades_exam ON public.grades(exam_id);
CREATE INDEX idx_grades_student ON public.grades(student_id);

CREATE TRIGGER grades_set_updated_at
  BEFORE UPDATE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

;
-- >>> 20260619135924_a404f218-d3ba-4057-8703-8b1ca426a782.sql
-- Tighten realtime.messages subscription policy:
-- 1. Require ':' separator in topic regex to prevent broad topics like "students:all"
--    from matching. Topics now must look like "attendance:<scope>".
-- 2. Add coverage for parent and student roles, scoped to per-user topics
--    (e.g. "notifications:user:<uid>", "grades:user:<uid>") so RLS-protected
--    realtime updates actually reach them.
DROP POLICY IF EXISTS "Realtime scoped by role" ON realtime.messages;

CREATE POLICY "Realtime scoped by role"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
    OR (
      public.has_role(auth.uid(), 'teacher'::app_role)
      AND realtime.topic() ~ '^(attendance|behavior|exams|notifications|classes|students):[A-Za-z0-9_-]+'
    )
    OR (
      public.has_role(auth.uid(), 'gate_monitor'::app_role)
      AND realtime.topic() ~ '^(card_scans|rfid_cards|notifications|gate):[A-Za-z0-9_-]+'
    )
    OR (
      public.has_role(auth.uid(), 'parent'::app_role)
      AND realtime.topic() = ('notifications:user:' || auth.uid()::text)
    )
    OR (
      public.has_role(auth.uid(), 'student'::app_role)
      AND realtime.topic() IN (
        'notifications:user:' || auth.uid()::text,
        'grades:user:' || auth.uid()::text,
        'attendance:user:' || auth.uid()::text
      )
    )
  );
;
-- >>> 20260619141555_27c59ea2-5aa1-4096-a037-a7811e1aa1ab.sql

-- RLS policies for avatars bucket. Files stored under "<user_id>/<filename>".
-- Each user can read/write only their own folder; everyone authenticated can read.

CREATE POLICY "Authenticated can read avatars"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'avatars');

CREATE POLICY "Users can upload to own avatar folder"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can update own avatar"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Users can delete own avatar"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

;
-- >>> 20260622094408_206bf797-e53a-4c04-976a-9d0521856541.sql

DROP POLICY IF EXISTS "Authenticated can view sessions" ON public.attendance_sessions;

CREATE TABLE IF NOT EXISTS public.class_teachers (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL,
  subject text NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE (class_id, teacher_id, subject)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.class_teachers TO authenticated;
GRANT ALL ON public.class_teachers TO service_role;
ALTER TABLE public.class_teachers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage class_teachers" ON public.class_teachers;
CREATE POLICY "Admins manage class_teachers" ON public.class_teachers
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role) OR public.has_role(auth.uid(), 'director'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role) OR public.has_role(auth.uid(), 'director'::app_role));

DROP POLICY IF EXISTS "Staff or self can view class_teachers" ON public.class_teachers;
CREATE POLICY "Staff or self can view class_teachers" ON public.class_teachers
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
    OR teacher_id = auth.uid()
  );

DROP TRIGGER IF EXISTS trg_class_teachers_updated_at ON public.class_teachers;
CREATE TRIGGER trg_class_teachers_updated_at
  BEFORE UPDATE ON public.class_teachers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "Scoped session reads" ON public.attendance_sessions
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
    OR teacher_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.class_teachers ct
      WHERE ct.class_id = attendance_sessions.class_id AND ct.teacher_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.students st
      WHERE st.class_id = attendance_sessions.class_id AND st.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.parent_student ps
      JOIN public.students st ON st.id = ps.student_id
      WHERE ps.parent_user_id = auth.uid() AND st.class_id = attendance_sessions.class_id
    )
  );

DROP POLICY IF EXISTS "Staff or self can view students" ON public.students;
CREATE POLICY "Staff or self can view students" ON public.students
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
    OR public.has_role(auth.uid(), 'gate_monitor'::app_role)
    OR user_id = auth.uid()
    OR (
      public.has_role(auth.uid(), 'teacher'::app_role)
      AND EXISTS (
        SELECT 1 FROM public.class_teachers ct
        WHERE ct.teacher_id = auth.uid() AND ct.class_id = students.class_id
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.parent_student ps
      WHERE ps.parent_user_id = auth.uid() AND ps.student_id = students.id
    )
  );

DROP POLICY IF EXISTS "Authenticated can read avatars" ON storage.objects;
CREATE POLICY "Users read own avatar or staff read all" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.has_role(auth.uid(), 'admin'::app_role)
      OR public.has_role(auth.uid(), 'director'::app_role)
      OR public.has_role(auth.uid(), 'supervisor'::app_role)
    )
  );

;
-- >>> 20260701213054_dec9def1-c238-46a6-8262-fd718ee0f6ae.sql

CREATE TABLE public.profile_audit_log (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  details JSONB,
  ip TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX profile_audit_log_user_id_idx ON public.profile_audit_log(user_id, created_at DESC);

GRANT SELECT, INSERT ON public.profile_audit_log TO authenticated;
GRANT ALL ON public.profile_audit_log TO service_role;

ALTER TABLE public.profile_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own audit rows" ON public.profile_audit_log
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own audit rows" ON public.profile_audit_log
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Admins read all audit rows" ON public.profile_audit_log
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

;
-- >>> 20260703114156_c3d5988a-5a27-4c6b-b4e6-f66df37d62d2.sql

-- 1) Parents can view attendance of their linked children
CREATE POLICY "Parents can view linked children attendance"
ON public.attendance_records
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.parent_student ps
    WHERE ps.parent_user_id = auth.uid()
      AND ps.student_id = attendance_records.student_id
  )
);

-- 2) Parents can view behavior of their linked children
CREATE POLICY "Parents can view linked children behavior"
ON public.behavior_records
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.parent_student ps
    WHERE ps.parent_user_id = auth.uid()
      AND ps.student_id = behavior_records.student_id
  )
);

-- 3) Scope teacher grade writes to classes the teacher is assigned to.
-- Split the broad "Staff manage grades" ALL policy into:
--   a) Management (admin/director/supervisor) — unrestricted
--   b) Teachers  — only for exams whose class matches a class_teachers row for them,
--                  AND the student belongs to that same class.
DROP POLICY IF EXISTS "Staff manage grades" ON public.grades;

CREATE POLICY "Management manage grades"
ON public.grades
FOR ALL
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'director'::app_role)
  OR has_role(auth.uid(), 'supervisor'::app_role)
)
WITH CHECK (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'director'::app_role)
  OR has_role(auth.uid(), 'supervisor'::app_role)
);

CREATE POLICY "Teachers manage grades for their classes"
ON public.grades
FOR ALL
TO authenticated
USING (
  has_role(auth.uid(), 'teacher'::app_role)
  AND EXISTS (
    SELECT 1
    FROM public.exams e
    JOIN public.class_teachers ct
      ON ct.class_id = e.class_id AND ct.teacher_id = auth.uid()
    JOIN public.students s
      ON s.id = grades.student_id AND s.class_id = e.class_id
    WHERE e.id = grades.exam_id
  )
)
WITH CHECK (
  has_role(auth.uid(), 'teacher'::app_role)
  AND EXISTS (
    SELECT 1
    FROM public.exams e
    JOIN public.class_teachers ct
      ON ct.class_id = e.class_id AND ct.teacher_id = auth.uid()
    JOIN public.students s
      ON s.id = grades.student_id AND s.class_id = e.class_id
    WHERE e.id = grades.exam_id
  )
);

;
-- >>> 20260705124304_6b69d3cd-2cda-478f-a5f4-9e62596bf942.sql

-- Tighten EXECUTE grants on SECURITY DEFINER functions.
-- RLS policies reference has_role/get_user_roles via the definer context, so
-- revoking from PUBLIC/anon does not break policy evaluation, it only stops
-- signed-out / anon callers from probing these functions directly.

REVOKE ALL ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_user_roles(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_roles(uuid) TO authenticated, service_role;

-- Overview stats: only management roles should count all rows platform-wide.
-- Wrap in an authorization check so a stray call from a lesser role errors out.
CREATE OR REPLACE FUNCTION public.get_overview_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'students', (SELECT count(*) FROM public.students),
    'cards', (SELECT count(*) FROM public.rfid_cards),
    'attendance', (SELECT count(*) FROM public.attendance_records),
    'notifications', (SELECT count(*) FROM public.notifications),
    'classes', (SELECT count(*) FROM public.classes),
    'scans', (SELECT count(*) FROM public.card_scans)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_overview_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated, service_role;

;
-- >>> 20260711192733_2fc66d59-eca7-4bab-8349-feac99d4c913.sql
-- Roles enum
CREATE TYPE public.app_role AS ENUM ('admin', 'director', 'supervisor', 'teacher', 'parent', 'student', 'gate_monitor');

-- Profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  preferred_language TEXT DEFAULT 'ar',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id UUID)
RETURNS SETOF app_role LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT role FROM public.user_roles WHERE user_id = _user_id $$;

CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));
CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can manage all roles" ON public.user_roles FOR ALL USING (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public
AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Classes
CREATE TABLE IF NOT EXISTS public.classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  level text,
  branch text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone authenticated can view classes" ON public.classes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage classes" ON public.classes FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'));

-- Students
CREATE TABLE IF NOT EXISTS public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  gender text CHECK (gender IN ('M','F')),
  date_of_birth date,
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  fake_email text,
  fake_phone text,
  user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_students_class ON public.students(class_id);
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view students" ON public.students FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff manage students" ON public.students FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Staff whitelist
CREATE TABLE IF NOT EXISTS public.staff_whitelist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL UNIQUE,
  role app_role NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.staff_whitelist ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage staff whitelist" ON public.staff_whitelist FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- Signup trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $$
DECLARE
  _name text;
  _whitelisted_role app_role;
  _requested_role app_role;
  _requested_text text;
BEGIN
  _name := COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name',''), NULLIF(NEW.raw_user_meta_data->>'name',''), NEW.email);
  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'), NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  SELECT role INTO _whitelisted_role FROM public.staff_whitelist WHERE full_name = _name LIMIT 1;

  _requested_text := NEW.raw_user_meta_data->>'requested_role';
  IF _requested_text IS NOT NULL AND _requested_text <> '' THEN
    BEGIN _requested_role := _requested_text::app_role;
    EXCEPTION WHEN others THEN _requested_role := NULL; END;
  END IF;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, COALESCE(_whitelisted_role, _requested_role, 'student'::app_role))
  ON CONFLICT (user_id, role) DO NOTHING;

  UPDATE public.students SET user_id = NEW.id WHERE full_name = _name AND user_id IS NULL;
  RETURN NEW;
END; $$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(UUID, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_roles(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(UUID, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_roles(UUID) TO authenticated;

-- RFID Cards
CREATE TABLE public.rfid_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL UNIQUE,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'active',
  note TEXT,
  assigned_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.rfid_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view cards" ON public.rfid_cards FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff manage cards" ON public.rfid_cards FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_rfid_cards_updated BEFORE UPDATE ON public.rfid_cards
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Card scans
CREATE TABLE public.card_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  direction TEXT NOT NULL DEFAULT 'in',
  gate_id TEXT,
  scanned_by UUID,
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_card_scans_scanned_at ON public.card_scans(scanned_at DESC);
CREATE INDEX idx_card_scans_card_uid ON public.card_scans(card_uid);
ALTER TABLE public.card_scans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view scans" ON public.card_scans FOR SELECT TO authenticated USING (true);
CREATE POLICY "Gate and staff can insert scans" ON public.card_scans FOR INSERT TO authenticated
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'gate_monitor'));
CREATE POLICY "Staff manage scans" ON public.card_scans FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));

-- Attendance
CREATE TABLE public.attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_date DATE NOT NULL DEFAULT CURRENT_DATE,
  period TEXT,
  subject TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_att_sessions_class_date ON public.attendance_sessions(class_id, session_date DESC);
CREATE TRIGGER trg_att_sessions_updated_at BEFORE UPDATE ON public.attendance_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view sessions" ON public.attendance_sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can manage sessions" ON public.attendance_sessions FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor') OR public.has_role(auth.uid(), 'teacher'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor') OR public.has_role(auth.uid(), 'teacher'));

CREATE TABLE public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present',
  note TEXT,
  justified_at TIMESTAMPTZ,
  justified_by UUID,
  justification_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, student_id),
  CHECK (status IN ('present','absent','late','excused'))
);
CREATE INDEX idx_att_records_student ON public.attendance_records(student_id);
CREATE INDEX idx_att_records_session ON public.attendance_records(session_id);
CREATE TRIGGER trg_att_records_updated_at BEFORE UPDATE ON public.attendance_records
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view records" ON public.attendance_records FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can manage records" ON public.attendance_records FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor') OR public.has_role(auth.uid(), 'teacher'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor') OR public.has_role(auth.uid(), 'teacher'));

-- Notifications
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_label TEXT,
  title TEXT NOT NULL,
  body TEXT,
  channel TEXT NOT NULL DEFAULT 'inapp',
  status TEXT NOT NULL DEFAULT 'sent',
  related_student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  read_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (channel IN ('inapp','email','sms')),
  CHECK (status IN ('sent','simulated','failed','read'))
);
CREATE INDEX idx_notif_recipient ON public.notifications(recipient_id, created_at DESC);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Recipient or staff can view" ON public.notifications FOR SELECT TO authenticated
  USING (recipient_id = auth.uid() OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE POLICY "Staff can insert" ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
CREATE POLICY "Recipient can mark read" ON public.notifications FOR UPDATE TO authenticated
  USING (recipient_id = auth.uid());

-- Grants (public-schema Data API access)
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE ON public.profiles TO authenticated;
GRANT INSERT ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
GRANT SELECT ON public.classes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.classes TO authenticated;
GRANT ALL ON public.classes TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.students TO authenticated;
GRANT ALL ON public.students TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.staff_whitelist TO authenticated;
GRANT ALL ON public.staff_whitelist TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.rfid_cards TO authenticated;
GRANT ALL ON public.rfid_cards TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.card_scans TO authenticated;
GRANT ALL ON public.card_scans TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance_sessions TO authenticated;
GRANT ALL ON public.attendance_sessions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance_records TO authenticated;
GRANT ALL ON public.attendance_records TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;

-- Realtime
ALTER TABLE public.classes REPLICA IDENTITY FULL;
ALTER TABLE public.students REPLICA IDENTITY FULL;
ALTER TABLE public.rfid_cards REPLICA IDENTITY FULL;
ALTER TABLE public.card_scans REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.classes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.students;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rfid_cards;
ALTER PUBLICATION supabase_realtime ADD TABLE public.card_scans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;

-- Seed classes + whitelist
INSERT INTO public.staff_whitelist (full_name, role, note)
VALUES ('بوكعاش يونس إدريس', 'admin', 'مسؤول رئيسي')
ON CONFLICT (full_name) DO UPDATE SET role = EXCLUDED.role;

INSERT INTO public.classes (name, level, branch) VALUES ('ج م ع ت 4', '1AS', 'جذع مشترك علوم وتكنولوجيا') ON CONFLICT (name) DO NOTHING;
INSERT INTO public.classes (name, level, branch) VALUES ('ج م أ 1', '1AS', 'جذع مشترك آداب') ON CONFLICT (name) DO NOTHING;
;
-- >>> 20260711192822_bb07800f-32b0-4637-84cb-81f51eea24f1.sql
-- School decisions/announcements
CREATE TABLE IF NOT EXISTS public.school_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  decision_type text NOT NULL DEFAULT 'announcement',
  body text,
  status text NOT NULL DEFAULT 'active',
  starts_at timestamptz DEFAULT now(),
  ends_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.behavior_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE,
  record_type text NOT NULL DEFAULT 'positive',
  points integer NOT NULL DEFAULT 0,
  title text NOT NULL,
  note text,
  recorded_by uuid,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.library_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  author text,
  item_type text NOT NULL DEFAULT 'book',
  total_copies integer NOT NULL DEFAULT 1,
  available_copies integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.library_loans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid REFERENCES public.library_items(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  loaned_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz,
  returned_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.school_trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  destination text,
  trip_date date,
  status text NOT NULL DEFAULT 'planned',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.trip_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid REFERENCES public.school_trips(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  consent_status text NOT NULL DEFAULT 'pending',
  attended boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trip_id, student_id)
);

CREATE TABLE IF NOT EXISTS public.exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  subject text NOT NULL,
  exam_date date,
  room text,
  status text NOT NULL DEFAULT 'scheduled',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS + policies + triggers for all above
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['school_decisions','behavior_records','library_items','library_loans','school_trips','trip_participants','exams']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=tbl AND policyname='Authenticated can view school admin data') THEN
      EXECUTE format('CREATE POLICY "Authenticated can view school admin data" ON public.%I FOR SELECT TO authenticated USING (true)', tbl);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=tbl AND policyname='Management can change school admin data') THEN
      EXECUTE format('CREATE POLICY "Management can change school admin data" ON public.%I FOR ALL TO authenticated USING (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor'')) WITH CHECK (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor''))', tbl);
    END IF;
    IF tbl <> 'trip_participants' AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_' || tbl || '_updated_at') THEN
      EXECUTE format('CREATE TRIGGER set_%I_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', tbl, tbl);
    END IF;
  END LOOP;
END $$;

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON public.school_decisions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.behavior_records TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.library_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.library_loans TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.school_trips TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.trip_participants TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.exams TO authenticated;
GRANT ALL ON public.school_decisions, public.behavior_records, public.library_items, public.library_loans, public.school_trips, public.trip_participants, public.exams TO service_role;

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.school_decisions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.behavior_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_loans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.school_trips;
ALTER PUBLICATION supabase_realtime ADD TABLE public.trip_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.exams;

-- Extra indexes
CREATE INDEX IF NOT EXISTS idx_attendance_records_created_at ON public.attendance_records (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rfid_cards_card_uid ON public.rfid_cards (card_uid);
CREATE INDEX IF NOT EXISTS idx_rfid_cards_student_id ON public.rfid_cards (student_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_school_decisions_status_starts_at ON public.school_decisions (status, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_students_user_id ON public.students (user_id);

-- Overview stats RPC
CREATE OR REPLACE FUNCTION public.get_overview_stats()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'students', (SELECT count(*) FROM public.students),
    'cards', (SELECT count(*) FROM public.rfid_cards),
    'attendance', (SELECT count(*) FROM public.attendance_records),
    'notifications', (SELECT count(*) FROM public.notifications),
    'classes', (SELECT count(*) FROM public.classes),
    'scans', (SELECT count(*) FROM public.card_scans)
  )
$$;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated;
;
-- >>> 20260711192907_af4cce9f-8d71-438f-9817-1158834484ee.sql
-- Tighten profiles policies (scope to authenticated)
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);

-- Students: role/self-scoped SELECT, plus teachers scoped to classes they teach
DROP POLICY IF EXISTS "Authenticated can view students" ON public.students;
DROP POLICY IF EXISTS "Staff or self can view students" ON public.students;
CREATE POLICY "Staff or self can view students" ON public.students FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR has_role(auth.uid(),'gate_monitor') OR (user_id = auth.uid())
    OR (has_role(auth.uid(),'teacher') AND EXISTS (
      SELECT 1 FROM public.attendance_sessions s WHERE s.teacher_id = auth.uid() AND s.class_id = students.class_id))
  );

-- rfid_cards: staff + gate + self
DROP POLICY IF EXISTS "Authenticated can view cards" ON public.rfid_cards;
CREATE POLICY "Staff can view cards" ON public.rfid_cards FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR has_role(auth.uid(),'gate_monitor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = rfid_cards.student_id AND s.user_id = auth.uid())
  );

-- card_scans: staff + gate + self
DROP POLICY IF EXISTS "Authenticated can view scans" ON public.card_scans;
CREATE POLICY "Staff can view scans" ON public.card_scans FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR has_role(auth.uid(),'gate_monitor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = card_scans.student_id AND s.user_id = auth.uid())
  );

-- Behavior: staff + self
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.behavior_records;
CREATE POLICY "Staff can view behavior" ON public.behavior_records FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR has_role(auth.uid(),'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = behavior_records.student_id AND s.user_id = auth.uid())
  );

-- Attendance: staff (teacher scoped to their sessions) + self
DROP POLICY IF EXISTS "Authenticated can view records" ON public.attendance_records;
DROP POLICY IF EXISTS "Staff or self can view attendance" ON public.attendance_records;
CREATE POLICY "Staff or self can view attendance" ON public.attendance_records FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR (has_role(auth.uid(),'teacher') AND EXISTS (
      SELECT 1 FROM public.attendance_sessions s WHERE s.id = attendance_records.session_id AND s.teacher_id = auth.uid()))
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = attendance_records.student_id AND s.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.library_loans;
CREATE POLICY "Staff or self can view loans" ON public.library_loans FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = library_loans.student_id AND s.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.trip_participants;
CREATE POLICY "Staff or self can view trip participants" ON public.trip_participants FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR has_role(auth.uid(),'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = trip_participants.student_id AND s.user_id = auth.uid())
  );

-- Add card scan mode/note/visitor columns
ALTER TABLE public.card_scans
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS note text,
  ADD COLUMN IF NOT EXISTS visitor_name text;
CREATE INDEX IF NOT EXISTS idx_card_scans_mode ON public.card_scans(mode);
CREATE INDEX IF NOT EXISTS idx_card_scans_student_scanned_at ON public.card_scans(student_id, scanned_at DESC);

-- Attendance justification workflow
CREATE OR REPLACE FUNCTION public.prevent_late_override()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status = 'late' AND NEW.status <> 'late'
     AND OLD.justified_at IS NULL AND NEW.justified_at IS NULL THEN
    RAISE EXCEPTION 'LATE_NOT_JUSTIFIED: لا يمكن تعديل حالة الطالب من "متأخر" قبل تبرير التأخر.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_prevent_late_override ON public.attendance_records;
CREATE TRIGGER trg_prevent_late_override BEFORE UPDATE ON public.attendance_records
  FOR EACH ROW EXECUTE FUNCTION public.prevent_late_override();

-- Staff whitelist by email (immutable)
ALTER TABLE public.staff_whitelist ADD COLUMN IF NOT EXISTS email text;
CREATE UNIQUE INDEX IF NOT EXISTS staff_whitelist_email_key ON public.staff_whitelist (lower(email)) WHERE email IS NOT NULL;

-- Rewrite handle_new_user: match staff_whitelist by email, no auto-link
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  _name text; _email text; _whitelisted_role app_role;
BEGIN
  _email := lower(NEW.email);
  _name := COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name',''), NULLIF(NEW.raw_user_meta_data->>'name',''), NEW.email);
  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'), NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  IF _email IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com') THEN
    INSERT INTO public.user_roles (user_id, role) VALUES
      (NEW.id, 'admin'::app_role), (NEW.id, 'director'::app_role), (NEW.id, 'supervisor'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    SELECT role INTO _whitelisted_role FROM public.staff_whitelist
      WHERE email IS NOT NULL AND lower(email) = _email LIMIT 1;
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, COALESCE(_whitelisted_role, 'student'::app_role))
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

-- Realtime subscription policy scoped by role
ALTER TABLE IF EXISTS realtime.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Staff can subscribe to realtime" ON realtime.messages;
DROP POLICY IF EXISTS "Realtime scoped by role" ON realtime.messages;
CREATE POLICY "Realtime scoped by role" ON realtime.messages FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor')
    OR (public.has_role(auth.uid(),'teacher') AND realtime.topic() ~ '^(attendance|behavior|exams|notifications|classes|students)(:|$)')
    OR (public.has_role(auth.uid(),'gate_monitor') AND realtime.topic() ~ '^(card_scans|rfid_cards|notifications|gate)(:|$)')
  );

-- Parent-student link
CREATE TABLE IF NOT EXISTS public.parent_student (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  relation text DEFAULT 'parent',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (parent_user_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.parent_student TO authenticated;
GRANT ALL ON public.parent_student TO service_role;
ALTER TABLE public.parent_student ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Parents see own links" ON public.parent_student FOR SELECT TO authenticated
  USING (parent_user_id = auth.uid() OR has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));
CREATE POLICY "Staff manage parent links" ON public.parent_student FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));
CREATE INDEX IF NOT EXISTS idx_parent_student_parent ON public.parent_student(parent_user_id);
CREATE INDEX IF NOT EXISTS idx_parent_student_student ON public.parent_student(student_id);
;
-- >>> 20260711193026_1257807e-9483-47f1-8170-cad1a0ac36f0.sql
CREATE TABLE IF NOT EXISTS public.grades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_id uuid NOT NULL REFERENCES public.exams(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  score numeric(5,2),
  max_score numeric(5,2) NOT NULL DEFAULT 20,
  remark text,
  entered_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (exam_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.grades TO authenticated;
GRANT ALL ON public.grades TO service_role;
ALTER TABLE public.grades ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_grades_exam ON public.grades(exam_id);
CREATE INDEX IF NOT EXISTS idx_grades_student ON public.grades(student_id);
CREATE TRIGGER grades_set_updated_at BEFORE UPDATE ON public.grades FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY "Students see own grades" ON public.grades FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.students s WHERE s.id = grades.student_id AND s.user_id = auth.uid()));
CREATE POLICY "Parents see linked children grades" ON public.grades FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.student_id = grades.student_id AND ps.parent_user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.class_teachers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL,
  subject text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (class_id, teacher_id, subject)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.class_teachers TO authenticated;
GRANT ALL ON public.class_teachers TO service_role;
ALTER TABLE public.class_teachers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage class_teachers" ON public.class_teachers FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director'));
CREATE POLICY "Staff or self can view class_teachers" ON public.class_teachers FOR SELECT TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR teacher_id = auth.uid());
CREATE TRIGGER trg_class_teachers_updated_at BEFORE UPDATE ON public.class_teachers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "Management manage grades" ON public.grades FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));
CREATE POLICY "Teachers manage grades for their classes" ON public.grades FOR ALL TO authenticated
  USING (has_role(auth.uid(),'teacher') AND EXISTS (
    SELECT 1 FROM public.exams e
    JOIN public.class_teachers ct ON ct.class_id = e.class_id AND ct.teacher_id = auth.uid()
    JOIN public.students s ON s.id = grades.student_id AND s.class_id = e.class_id
    WHERE e.id = grades.exam_id))
  WITH CHECK (has_role(auth.uid(),'teacher') AND EXISTS (
    SELECT 1 FROM public.exams e
    JOIN public.class_teachers ct ON ct.class_id = e.class_id AND ct.teacher_id = auth.uid()
    JOIN public.students s ON s.id = grades.student_id AND s.class_id = e.class_id
    WHERE e.id = grades.exam_id));

DROP POLICY IF EXISTS "Authenticated can view sessions" ON public.attendance_sessions;
CREATE POLICY "Scoped session reads" ON public.attendance_sessions FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR teacher_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.class_teachers ct WHERE ct.class_id = attendance_sessions.class_id AND ct.teacher_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.students st WHERE st.class_id = attendance_sessions.class_id AND st.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.parent_student ps JOIN public.students st ON st.id = ps.student_id
               WHERE ps.parent_user_id = auth.uid() AND st.class_id = attendance_sessions.class_id)
  );

CREATE POLICY "Parents can view linked children attendance" ON public.attendance_records FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.parent_user_id = auth.uid() AND ps.student_id = attendance_records.student_id));
CREATE POLICY "Parents can view linked children behavior" ON public.behavior_records FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.parent_user_id = auth.uid() AND ps.student_id = behavior_records.student_id));

DROP POLICY IF EXISTS "Staff or self can view students" ON public.students;
CREATE POLICY "Staff or self can view students" ON public.students FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR has_role(auth.uid(),'gate_monitor') OR user_id = auth.uid()
    OR (has_role(auth.uid(),'teacher') AND EXISTS (
      SELECT 1 FROM public.class_teachers ct WHERE ct.teacher_id = auth.uid() AND ct.class_id = students.class_id))
    OR EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.parent_user_id = auth.uid() AND ps.student_id = students.id)
  );

CREATE TABLE IF NOT EXISTS public.profile_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action text NOT NULL,
  details jsonb,
  ip text,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS profile_audit_log_user_id_idx ON public.profile_audit_log(user_id, created_at DESC);
GRANT SELECT, INSERT ON public.profile_audit_log TO authenticated;
GRANT ALL ON public.profile_audit_log TO service_role;
ALTER TABLE public.profile_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own audit rows" ON public.profile_audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users read own audit rows" ON public.profile_audit_log FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins read all audit rows" ON public.profile_audit_log FOR SELECT TO authenticated USING (has_role(auth.uid(),'admin'));

-- Avatars bucket policies (bucket created separately)
CREATE POLICY "Users read own avatar or staff read all" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'avatars' AND ((storage.foldername(name))[1] = auth.uid()::text
    OR has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')));
CREATE POLICY "Users can upload to own avatar folder" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Users can update own avatar" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Users can delete own avatar" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE OR REPLACE FUNCTION public.get_overview_stats()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '28000'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'students', (SELECT count(*) FROM public.students),
    'cards', (SELECT count(*) FROM public.rfid_cards),
    'attendance', (SELECT count(*) FROM public.attendance_records),
    'notifications', (SELECT count(*) FROM public.notifications),
    'classes', (SELECT count(*) FROM public.classes),
    'scans', (SELECT count(*) FROM public.card_scans)
  );
END; $$;
REVOKE ALL ON FUNCTION public.get_overview_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_user_roles(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_roles(uuid) TO authenticated, service_role;

DROP POLICY IF EXISTS "Realtime scoped by role" ON realtime.messages;
CREATE POLICY "Realtime scoped by role" ON realtime.messages FOR SELECT TO authenticated
  USING (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
    OR (has_role(auth.uid(),'teacher') AND realtime.topic() ~ '^(attendance|behavior|exams|notifications|classes|students):[A-Za-z0-9_-]+')
    OR (has_role(auth.uid(),'gate_monitor') AND realtime.topic() ~ '^(card_scans|rfid_cards|notifications|gate):[A-Za-z0-9_-]+')
    OR (has_role(auth.uid(),'parent') AND realtime.topic() = ('notifications:user:' || auth.uid()::text))
    OR (has_role(auth.uid(),'student') AND realtime.topic() IN (
        'notifications:user:' || auth.uid()::text,
        'grades:user:' || auth.uid()::text,
        'attendance:user:' || auth.uid()::text))
  );
;
-- >>> 20260720143700_c7ac1b8f-8458-409b-9930-b165585916ca.sql

-- Whitelist owner emails as admin (idempotent)
INSERT INTO public.staff_whitelist (email, full_name, role, note)
VALUES
  ('boukaachey@gmail.com', 'Owner (boukaachey)', 'admin', 'Site owner'),
  ('boukaacheyounes@gmail.com', 'Owner (boukaacheyounes)', 'admin', 'Site owner')
ON CONFLICT (full_name) DO UPDATE
  SET email = EXCLUDED.email, role = 'admin', note = EXCLUDED.note;

-- If accounts already exist, grant admin/director/supervisor now
INSERT INTO public.user_roles (user_id, role)
SELECT u.id, r
FROM auth.users u
CROSS JOIN unnest(ARRAY['admin','director','supervisor']::public.app_role[]) r
WHERE lower(u.email) IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com')
ON CONFLICT (user_id, role) DO NOTHING;

;
-- >>> 20260722202100_9854dc50-0c9b-4bac-a181-d10f80d38140.sql

-- 1) Lock down SECURITY DEFINER functions from anon (and public)
REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_user_roles(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_roles(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_overview_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- 2) Restrict overly-permissive SELECT policies to staff/teacher roles
DROP POLICY IF EXISTS "Anyone authenticated can view classes" ON public.classes;
CREATE POLICY "Staff and teachers can view classes"
ON public.classes FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(),'admin') OR
  public.has_role(auth.uid(),'director') OR
  public.has_role(auth.uid(),'supervisor') OR
  public.has_role(auth.uid(),'teacher')
);

DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.exams;
CREATE POLICY "Staff and teachers can view exams"
ON public.exams FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(),'admin') OR
  public.has_role(auth.uid(),'director') OR
  public.has_role(auth.uid(),'supervisor') OR
  public.has_role(auth.uid(),'teacher')
);

DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.library_items;
CREATE POLICY "Staff and teachers can view library items"
ON public.library_items FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(),'admin') OR
  public.has_role(auth.uid(),'director') OR
  public.has_role(auth.uid(),'supervisor') OR
  public.has_role(auth.uid(),'teacher')
);

DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.school_decisions;
CREATE POLICY "Staff and teachers can view school decisions"
ON public.school_decisions FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(),'admin') OR
  public.has_role(auth.uid(),'director') OR
  public.has_role(auth.uid(),'supervisor') OR
  public.has_role(auth.uid(),'teacher')
);

DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.school_trips;
CREATE POLICY "Staff and teachers can view school trips"
ON public.school_trips FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(),'admin') OR
  public.has_role(auth.uid(),'director') OR
  public.has_role(auth.uid(),'supervisor') OR
  public.has_role(auth.uid(),'teacher')
);

;
-- >>> 20260804225630_a876e452-a3a0-4183-b3a4-d8cdc45cf731.sql
REVOKE EXECUTE ON FUNCTION public.get_overview_stats() FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.get_user_roles(uuid) FROM anon, authenticated, public;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated, public;
REVOKE EXECUTE ON FUNCTION public.prevent_late_override() FROM anon, authenticated, public;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_roles(uuid) TO service_role;
;
-- >>> 20260906131002_bdb4ca4c-a2b6-477e-88f2-389adf8e2357.sql
CREATE OR REPLACE FUNCTION public.set_appearance_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_appearance_updated_at() FROM PUBLIC, anon, authenticated;

CREATE TABLE public.appearance_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  is_global BOOLEAN NOT NULL DEFAULT false,
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX appearance_settings_user_key ON public.appearance_settings (user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX appearance_settings_global_key ON public.appearance_settings ((is_global)) WHERE is_global;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.appearance_settings TO authenticated;
GRANT ALL ON public.appearance_settings TO service_role;

ALTER TABLE public.appearance_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Signed-in users can read appearance settings"
  ON public.appearance_settings FOR SELECT TO authenticated
  USING (is_global OR user_id = auth.uid());

CREATE POLICY "Users manage their own appearance"
  ON public.appearance_settings FOR ALL TO authenticated
  USING (user_id = auth.uid() AND NOT is_global)
  WITH CHECK (user_id = auth.uid() AND NOT is_global);

CREATE POLICY "Admins manage the shared appearance"
  ON public.appearance_settings FOR ALL TO authenticated
  USING (is_global AND public.has_role(auth.uid(), 'admin'))
  WITH CHECK (is_global AND public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER appearance_settings_updated_at
  BEFORE UPDATE ON public.appearance_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_appearance_updated_at();
;
-- >>> 20260908075318_b015cedc-f8c4-478b-b0f2-55d99b539f56.sql

-- 1) SCHEDULE SLOTS
CREATE TABLE public.schedule_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject text NOT NULL,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time time NOT NULL,
  end_time time NOT NULL,
  room text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.schedule_slots TO authenticated;
GRANT ALL ON public.schedule_slots TO service_role;
ALTER TABLE public.schedule_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "schedule read" ON public.schedule_slots FOR SELECT TO authenticated USING (true);
CREATE POLICY "schedule write" ON public.schedule_slots FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'teacher'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'teacher'));
CREATE TRIGGER trg_schedule_slots_updated_at BEFORE UPDATE ON public.schedule_slots FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_schedule_slots_class ON public.schedule_slots(class_id, weekday, start_time);

-- 2) HOMEWORK
CREATE TABLE public.homework (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject text NOT NULL,
  title text NOT NULL,
  description text,
  due_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.homework TO authenticated;
GRANT ALL ON public.homework TO service_role;
ALTER TABLE public.homework ENABLE ROW LEVEL SECURITY;
CREATE POLICY "homework read" ON public.homework FOR SELECT TO authenticated USING (true);
CREATE POLICY "homework write" ON public.homework FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'teacher'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'teacher'));
CREATE TRIGGER trg_homework_updated_at BEFORE UPDATE ON public.homework FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_homework_class_due ON public.homework(class_id, due_date DESC);

-- 3) STUDENT GOALS
CREATE TABLE public.student_goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  progress smallint NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  target_date date,
  done boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.student_goals TO authenticated;
GRANT ALL ON public.student_goals TO service_role;
ALTER TABLE public.student_goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "goals owner all" ON public.student_goals FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid()));
CREATE POLICY "goals staff read" ON public.student_goals FOR SELECT TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_student_goals_updated_at BEFORE UPDATE ON public.student_goals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_student_goals_student ON public.student_goals(student_id);

-- 4) ABSENCE JUSTIFICATIONS
CREATE TABLE public.absence_justifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  record_id uuid REFERENCES public.attendance_records(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  absence_date date,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.absence_justifications TO authenticated;
GRANT ALL ON public.absence_justifications TO service_role;
ALTER TABLE public.absence_justifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "justif owner read" ON public.absence_justifications FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid()));
CREATE POLICY "justif owner insert" ON public.absence_justifications FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid()));
CREATE POLICY "justif staff all" ON public.absence_justifications FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_absence_justifications_updated_at BEFORE UPDATE ON public.absence_justifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_absence_justifications_student ON public.absence_justifications(student_id, created_at DESC);

;
-- >>> 20260924171244_4ef2f925-a88a-43e4-a3f8-3ef898c38502.sql
-- Roles enum
CREATE TYPE public.app_role AS ENUM ('admin', 'director', 'supervisor', 'teacher', 'parent', 'student', 'gate_monitor');

-- Profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  preferred_language TEXT DEFAULT 'ar',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.get_user_roles(_user_id UUID)
RETURNS SETOF app_role LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.user_roles WHERE user_id = _user_id
$$;

CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));
CREATE POLICY "Users can create own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can view own roles" ON public.user_roles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can manage all roles" ON public.user_roles FOR ALL USING (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(UUID, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_roles(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(UUID, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_roles(UUID) TO authenticated;

-- Classes
CREATE TABLE public.classes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  level text,
  branch text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone authenticated can view classes" ON public.classes FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins manage classes" ON public.classes FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director'));

-- Students
CREATE TABLE public.students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  gender text CHECK (gender IN ('M','F')),
  date_of_birth date,
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  fake_email text,
  fake_phone text,
  user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_students_class ON public.students(class_id);
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view students" ON public.students FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff manage students" ON public.students FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Staff whitelist
CREATE TABLE public.staff_whitelist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL UNIQUE,
  role app_role NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.staff_whitelist ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage staff whitelist" ON public.staff_whitelist FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- RFID Cards
CREATE TABLE public.rfid_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL UNIQUE,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'active',
  note TEXT,
  assigned_at TIMESTAMPTZ DEFAULT now(),
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.rfid_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view cards" ON public.rfid_cards FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff manage cards" ON public.rfid_cards FOR ALL TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_rfid_cards_updated BEFORE UPDATE ON public.rfid_cards
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Card scans
CREATE TABLE public.card_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_uid TEXT NOT NULL,
  student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  direction TEXT NOT NULL DEFAULT 'in',
  gate_id TEXT,
  scanned_by UUID,
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_card_scans_scanned_at ON public.card_scans(scanned_at DESC);
CREATE INDEX idx_card_scans_card_uid ON public.card_scans(card_uid);
ALTER TABLE public.card_scans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view scans" ON public.card_scans FOR SELECT TO authenticated USING (true);
CREATE POLICY "Gate and staff can insert scans" ON public.card_scans FOR INSERT TO authenticated
WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'gate_monitor'));
CREATE POLICY "Staff manage scans" ON public.card_scans FOR ALL TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));

-- Attendance
CREATE TABLE public.attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_date DATE NOT NULL DEFAULT CURRENT_DATE,
  period TEXT,
  subject TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_att_sessions_class_date ON public.attendance_sessions(class_id, session_date DESC);
CREATE TRIGGER trg_att_sessions_updated_at BEFORE UPDATE ON public.attendance_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view sessions" ON public.attendance_sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can manage sessions" ON public.attendance_sessions FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));

CREATE TABLE public.attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present',
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, student_id),
  CHECK (status IN ('present','absent','late','excused'))
);
CREATE INDEX idx_att_records_student ON public.attendance_records(student_id);
CREATE INDEX idx_att_records_session ON public.attendance_records(session_id);
CREATE TRIGGER trg_att_records_updated_at BEFORE UPDATE ON public.attendance_records
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can view records" ON public.attendance_records FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can manage records" ON public.attendance_records FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));

-- Notifications
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_label TEXT,
  title TEXT NOT NULL,
  body TEXT,
  channel TEXT NOT NULL DEFAULT 'inapp',
  status TEXT NOT NULL DEFAULT 'sent',
  related_student_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
  read_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (channel IN ('inapp','email','sms')),
  CHECK (status IN ('sent','simulated','failed','read'))
);
CREATE INDEX idx_notif_recipient ON public.notifications(recipient_id, created_at DESC);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Recipient or staff can view" ON public.notifications FOR SELECT TO authenticated
  USING (recipient_id = auth.uid() OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE POLICY "Staff can insert" ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
CREATE POLICY "Recipient can mark read" ON public.notifications FOR UPDATE TO authenticated USING (recipient_id = auth.uid());

-- Admin/behavior/library/trips/exams
CREATE TABLE public.school_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  decision_type text NOT NULL DEFAULT 'announcement',
  body text,
  status text NOT NULL DEFAULT 'active',
  starts_at timestamptz DEFAULT now(),
  ends_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.behavior_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE,
  record_type text NOT NULL DEFAULT 'positive',
  points integer NOT NULL DEFAULT 0,
  title text NOT NULL,
  note text,
  recorded_by uuid,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.library_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  author text,
  item_type text NOT NULL DEFAULT 'book',
  total_copies integer NOT NULL DEFAULT 1,
  available_copies integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.library_loans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid REFERENCES public.library_items(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  loaned_at timestamptz NOT NULL DEFAULT now(),
  due_at timestamptz,
  returned_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.school_trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  destination text,
  trip_date date,
  status text NOT NULL DEFAULT 'planned',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.trip_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid REFERENCES public.school_trips(id) ON DELETE CASCADE NOT NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE CASCADE NOT NULL,
  consent_status text NOT NULL DEFAULT 'pending',
  attended boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trip_id, student_id)
);
CREATE TABLE public.exams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  subject text NOT NULL,
  exam_date date,
  room text,
  status text NOT NULL DEFAULT 'scheduled',
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['school_decisions','behavior_records','library_items','library_loans','school_trips','trip_participants','exams']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
    EXECUTE format('CREATE POLICY "Authenticated can view school admin data" ON public.%I FOR SELECT TO authenticated USING (true)', tbl);
    EXECUTE format('CREATE POLICY "Management can change school admin data" ON public.%I FOR ALL TO authenticated USING (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor'')) WITH CHECK (public.has_role(auth.uid(), ''admin'') OR public.has_role(auth.uid(), ''director'') OR public.has_role(auth.uid(), ''supervisor''))', tbl);
    IF tbl <> 'trip_participants' THEN
      EXECUTE format('CREATE TRIGGER set_%I_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', tbl, tbl);
    END IF;
  END LOOP;
END $$;

-- Data API grants for every table created above
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['profiles','user_roles','classes','students','staff_whitelist','rfid_cards','card_scans','attendance_sessions','attendance_records','notifications','school_decisions','behavior_records','library_items','library_loans','school_trips','trip_participants','exams']
  LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', tbl);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', tbl);
  END LOOP;
END $$;

-- Realtime
ALTER TABLE public.classes REPLICA IDENTITY FULL;
ALTER TABLE public.students REPLICA IDENTITY FULL;
ALTER TABLE public.rfid_cards REPLICA IDENTITY FULL;
ALTER TABLE public.card_scans REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.classes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.students;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rfid_cards;
ALTER PUBLICATION supabase_realtime ADD TABLE public.card_scans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.school_decisions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.behavior_records;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.library_loans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.school_trips;
ALTER PUBLICATION supabase_realtime ADD TABLE public.trip_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.exams;

-- Whitelist
INSERT INTO public.staff_whitelist (full_name, role, note)
VALUES ('بوكعاش يونس إدريس', 'admin', 'مسؤول رئيسي')
ON CONFLICT (full_name) DO UPDATE SET role = EXCLUDED.role;

-- Seed classes
INSERT INTO public.classes (name, level, branch) VALUES
  ('ج م ع ت 4', '1AS', 'جذع مشترك علوم وتكنولوجيا'),
  ('ج م أ 1', '1AS', 'جذع مشترك آداب');

-- Seed students
INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone)
SELECT s.full_name, s.gender, s.dob::date, c.id, s.email, s.phone
FROM (VALUES
  ('ابن خرورو عبد الرحمان','M','2009-11-05','student93810@idaroom.test','+213524942603'),
  ('ابن مناح أروى','F','2010-11-03','student13278@idaroom.test','+213546913810'),
  ('بن جامع أريج نور الهدى','F','2010-12-01','student42098@idaroom.test','+213539958838'),
  ('بن سماعين بلال','M','2010-08-13','student28289@idaroom.test','+213523756669'),
  ('بن عامر رنيم','F','2010-06-21','student98696@idaroom.test','+213583197857'),
  ('بن قدواد ندى حبيبة','F','2010-09-14','student21395@idaroom.test','+213589254563'),
  ('بوزيتونة ليله','F','2011-03-23','student65302@idaroom.test','+213514265799'),
  ('بوعبيد ملاك','F','2010-01-05','student13905@idaroom.test','+213522575562'),
  ('بوعصيدة أمينة','F','2010-04-10','student38657@idaroom.test','+213541227216'),
  ('بوكعاش يونس إدريس','M','2011-03-07','student76237@idaroom.test','+213590801586'),
  ('حركاتي محمد الصالح','M','2009-05-06','student13478@idaroom.test','+213585329037'),
  ('حيرش محمد تميم','M','2010-11-04','student36062@idaroom.test','+213597226012'),
  ('خناوي ألاء الرحمان','F','2010-06-07','student81426@idaroom.test','+213566306997'),
  ('خيري نسرين','F','2011-01-19','student38893@idaroom.test','+213570291817'),
  ('سوالمية محمد الصالح','M','2009-04-06','student87236@idaroom.test','+213547338124'),
  ('شكارلي محمد بهاء الدين','M','2010-09-11','student10851@idaroom.test','+213531429110'),
  ('شوابية قصي','M','2010-10-21','student65392@idaroom.test','+213555667651'),
  ('عباس حداد فزيل مولود','M','2010-06-15','student46421@idaroom.test','+213530868105'),
  ('عبد الرزاق يوسف','M','2010-07-06','student38221@idaroom.test','+213555176955'),
  ('عمرو عياش أنفال','F','2011-01-24','student23396@idaroom.test','+213522448136'),
  ('فاضل اياد شمس الدين','M','2010-07-30','student59797@idaroom.test','+213522981052'),
  ('قادة أمنية','F','2010-07-05','student57052@idaroom.test','+213556164955'),
  ('قجال رائد نزار','M','2010-01-10','student89131@idaroom.test','+213545503389'),
  ('قروي جهينة أناييس','F','2010-06-09','student15695@idaroom.test','+213571662963'),
  ('قليل نور مايا','F','2010-10-09','student80284@idaroom.test','+213526753883'),
  ('كحول زكريا','M','2010-05-27','student59615@idaroom.test','+213520576383'),
  ('كحول يحي','M','2010-05-27','student82357@idaroom.test','+213549349722'),
  ('لعور نريمان','F','2010-03-18','student92397@idaroom.test','+213593016315'),
  ('منتوري نادر','M','2010-01-18','student57400@idaroom.test','+213587490893'),
  ('ميمون عبد الله','M','2010-09-19','student35203@idaroom.test','+213519335534'),
  ('ميمون نجيب','M','2009-06-07','student16006@idaroom.test','+213598753260'),
  ('يخلف إياد عبد الرحيم','M','2010-08-12','student39871@idaroom.test','+213548840994'),
  ('تواتي إيناس','F','2010-01-01','student20458@idaroom.test','+213541244663'),
  ('قدوري إيناس','F','2010-01-01','student23238@idaroom.test','+213561019678')
) AS s(full_name, gender, dob, email, phone)
CROSS JOIN public.classes c WHERE c.name = 'ج م ع ت 4';

INSERT INTO public.students (full_name, gender, date_of_birth, class_id, fake_email, fake_phone)
SELECT s.full_name, s.gender, s.dob::date, c.id, s.email, s.phone
FROM (VALUES
  ('الخزعلي علي','M','2010-11-16','student56566@idaroom.test','+213538119557'),
  ('بن جامع عبدالرحمان','M','2009-03-19','student97841@idaroom.test','+213545833156'),
  ('بن فضة اسيل ندي الريحان','F','2011-01-30','student99593@idaroom.test','+213596977837'),
  ('بن فيسح عائشة','F','2011-03-05','student19358@idaroom.test','+213591756179'),
  ('بوخالفة رامي','M','2010-11-10','student93227@idaroom.test','+213532969840'),
  ('بوخالفة هارون الرشيد','M','2009-10-17','student80010@idaroom.test','+213542857966'),
  ('بودرياسي إبراهيم خليل','M','2009-09-29','student31417@idaroom.test','+213572043515'),
  ('بودفة زينب','F','2007-05-17','student59735@idaroom.test','+213546231783'),
  ('بوسالم رنا مرام','F','2010-09-03','student93886@idaroom.test','+213584752529'),
  ('بوشيلاون محمد وليد','M','2010-11-27','student38785@idaroom.test','+213553524491'),
  ('بوكرو حمزة','M','2010-03-19','student17331@idaroom.test','+213540742311'),
  ('بوهيدل سراج الدين','M','2010-04-08','student14207@idaroom.test','+213552339391'),
  ('جبلية رقية لجين','F','2010-01-03','student62581@idaroom.test','+213545935572'),
  ('جلواط سامي شعيب','M','2009-06-24','student18675@idaroom.test','+213538317637'),
  ('خنفوسي محمد فراس','M','2010-04-25','student84341@idaroom.test','+213552235350'),
  ('دالي ريم','F','2011-02-03','student37869@idaroom.test','+213597971488'),
  ('دحدوح شعيب','M','2008-09-15','student75435@idaroom.test','+213563100814'),
  ('رزاق اية','F','2010-07-22','student94259@idaroom.test','+213571586053'),
  ('سبيح دينا نورهان','F','2008-08-03','student28726@idaroom.test','+213545551614'),
  ('سوفي عبد المعز','M','2009-06-02','student28301@idaroom.test','+213543101783'),
  ('سيابة شيماء شروق','F','2010-07-05','student83579@idaroom.test','+213582340307'),
  ('شريبط عبد المعم','M','2010-03-21','student44438@idaroom.test','+213588461803'),
  ('شريط أشواق','F','2008-08-05','student66155@idaroom.test','+213588320463'),
  ('علالوش أمير خليل','M','2010-03-02','student62350@idaroom.test','+213558586340'),
  ('عوار محمد تقي الدين','M','2009-03-17','student38746@idaroom.test','+213528566572'),
  ('لكحل نزيم إسلام','M','2011-01-04','student76784@idaroom.test','+213576238574'),
  ('مهني لميس رتاج','F','2008-08-21','student21915@idaroom.test','+213516323852'),
  ('عميور اسيل','F','2010-01-07','student24371@idaroom.test','+213530514014'),
  ('عابر محمد وسيم','M','2009-10-06','student92240@idaroom.test','+213531472420'),
  ('نسمي باي ضياء عبد العزيز','F','2009-05-22','student99192@idaroom.test','+213566661351'),
  ('وغليسي دعاء','F','2010-07-27','student88172@idaroom.test','+213518526544'),
  ('لمداوي جاسمين أريج','F','2010-03-26','student60432@idaroom.test','+213561220073'),
  ('إينوش نهال رقية','F','2009-02-06','student88104@idaroom.test','+213572820592'),
  ('أحميدة محمد جابر','M','2010-02-20','student79352@idaroom.test','+213543744231'),
  ('غريب سامي اياد','M','2009-04-03','student82512@idaroom.test','+213511540956'),
  ('وادي محمد نضال','M','2010-11-22','student99166@idaroom.test','+213525374874')
) AS s(full_name, gender, dob, email, phone)
CROSS JOIN public.classes c WHERE c.name = 'ج م أ 1';

-- Profile + role provisioning on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _name text;
  _email text;
  _whitelisted_role app_role;
  _requested_role app_role;
  _requested_text text;
BEGIN
  _email := lower(NEW.email);
  _name := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NEW.email
  );

  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'), NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  IF _email IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com') THEN
    INSERT INTO public.user_roles (user_id, role) VALUES
      (NEW.id, 'admin'::app_role),
      (NEW.id, 'director'::app_role),
      (NEW.id, 'supervisor'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    SELECT role INTO _whitelisted_role FROM public.staff_whitelist WHERE full_name = _name LIMIT 1;
    _requested_text := NEW.raw_user_meta_data->>'requested_role';
    IF _requested_text IS NOT NULL AND _requested_text <> '' THEN
      BEGIN _requested_role := _requested_text::app_role;
      EXCEPTION WHEN others THEN _requested_role := NULL; END;
    END IF;
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, COALESCE(_whitelisted_role, _requested_role, 'student'::app_role))
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  UPDATE public.students SET user_id = NEW.id WHERE full_name = _name AND user_id IS NULL;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Seed demo content
INSERT INTO public.library_items (title, author, item_type, total_copies, available_copies) VALUES
  ('كتاب الرياضيات — سنة رابعة متوسط','وزارة التربية','book',20,20),
  ('كتاب اللغة العربية — سنة أولى ثانوي','وزارة التربية','book',18,18);

INSERT INTO public.school_decisions (title, decision_type, body, status)
VALUES ('اجتماع إداري تجريبي','announcement','قرار تجريبي للتأكد من عمل صفحة الإدارة والتحديث الفوري.','active');
;
-- >>> 20260924171330_3de018d4-3212-4983-94a4-25e913114b59.sql
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS idx_attendance_records_created_at ON public.attendance_records (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rfid_cards_card_uid ON public.rfid_cards (card_uid);
CREATE INDEX IF NOT EXISTS idx_rfid_cards_student_id ON public.rfid_cards (student_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_school_decisions_status_starts_at ON public.school_decisions (status, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_students_user_id ON public.students (user_id);

CREATE OR REPLACE FUNCTION public.get_overview_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'students', (SELECT count(*) FROM public.students),
    'cards', (SELECT count(*) FROM public.rfid_cards),
    'attendance', (SELECT count(*) FROM public.attendance_records),
    'notifications', (SELECT count(*) FROM public.notifications),
    'classes', (SELECT count(*) FROM public.classes),
    'scans', (SELECT count(*) FROM public.card_scans)
  )
$$;
REVOKE EXECUTE ON FUNCTION public.get_overview_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated;

-- profiles: authenticated only
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));
CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (auth.uid() = id);

-- user_roles
DROP POLICY IF EXISTS "Users can view own roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can manage all roles" ON public.user_roles;
CREATE POLICY "Users can view own roles" ON public.user_roles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins can manage all roles" ON public.user_roles
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- students
DROP POLICY IF EXISTS "Authenticated can view students" ON public.students;
CREATE POLICY "Staff or self can view students" ON public.students
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR public.has_role(auth.uid(), 'gate_monitor')
    OR user_id = auth.uid()
  );

-- rfid_cards
DROP POLICY IF EXISTS "Authenticated can view cards" ON public.rfid_cards;
CREATE POLICY "Staff can view cards" ON public.rfid_cards
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'gate_monitor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = rfid_cards.student_id AND s.user_id = auth.uid())
  );

-- card_scans
DROP POLICY IF EXISTS "Authenticated can view scans" ON public.card_scans;
CREATE POLICY "Staff can view scans" ON public.card_scans
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'gate_monitor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = card_scans.student_id AND s.user_id = auth.uid())
  );

-- behavior_records
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.behavior_records;
CREATE POLICY "Staff can view behavior" ON public.behavior_records
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = behavior_records.student_id AND s.user_id = auth.uid())
  );

-- attendance_records
DROP POLICY IF EXISTS "Authenticated can view records" ON public.attendance_records;
CREATE POLICY "Staff or self can view attendance" ON public.attendance_records
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = attendance_records.student_id AND s.user_id = auth.uid())
  );

-- library_loans
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.library_loans;
CREATE POLICY "Staff or self can view loans" ON public.library_loans
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = library_loans.student_id AND s.user_id = auth.uid())
  );

-- trip_participants
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.trip_participants;
CREATE POLICY "Staff or self can view trip participants" ON public.trip_participants
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'teacher')
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = trip_participants.student_id AND s.user_id = auth.uid())
  );

ALTER TABLE public.card_scans
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS note text,
  ADD COLUMN IF NOT EXISTS visitor_name text;
CREATE INDEX IF NOT EXISTS idx_card_scans_mode ON public.card_scans(mode);
CREATE INDEX IF NOT EXISTS idx_card_scans_student_scanned_at ON public.card_scans(student_id, scanned_at DESC);
;
-- >>> 20260924171540_352e3e5f-3116-4200-97fd-1b4a300b2dc9.sql
ALTER TABLE public.staff_whitelist ADD COLUMN IF NOT EXISTS email text;
CREATE UNIQUE INDEX IF NOT EXISTS staff_whitelist_email_key ON public.staff_whitelist (lower(email)) WHERE email IS NOT NULL;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _name text;
  _email text;
  _whitelisted_role app_role;
BEGIN
  _email := lower(NEW.email);
  _name := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NEW.email
  );

  INSERT INTO public.profiles (id, full_name, preferred_language, avatar_url)
  VALUES (NEW.id, _name, COALESCE(NEW.raw_user_meta_data->>'preferred_language','ar'), NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
    updated_at = now();

  IF _email IN ('boukaachey@gmail.com','boukaacheyounes@gmail.com') THEN
    INSERT INTO public.user_roles (user_id, role) VALUES
      (NEW.id, 'admin'::app_role),
      (NEW.id, 'director'::app_role),
      (NEW.id, 'supervisor'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    SELECT role INTO _whitelisted_role
      FROM public.staff_whitelist
      WHERE email IS NOT NULL AND lower(email) = _email
      LIMIT 1;
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, COALESCE(_whitelisted_role, 'student'::app_role))
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

ALTER TABLE public.attendance_records
  ADD COLUMN IF NOT EXISTS justified_at timestamptz,
  ADD COLUMN IF NOT EXISTS justified_by uuid,
  ADD COLUMN IF NOT EXISTS justification_note text;

CREATE OR REPLACE FUNCTION public.prevent_late_override()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'late'
     AND NEW.status <> 'late'
     AND OLD.justified_at IS NULL
     AND NEW.justified_at IS NULL THEN
    RAISE EXCEPTION 'LATE_NOT_JUSTIFIED: لا يمكن تعديل حالة الطالب من "متأخر" قبل تبرير التأخر.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_prevent_late_override ON public.attendance_records;
CREATE TRIGGER trg_prevent_late_override
BEFORE UPDATE ON public.attendance_records
FOR EACH ROW EXECUTE FUNCTION public.prevent_late_override();

CREATE TABLE IF NOT EXISTS public.parent_student (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  relation text DEFAULT 'parent',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (parent_user_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.parent_student TO authenticated;
GRANT ALL ON public.parent_student TO service_role;
ALTER TABLE public.parent_student ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Parents see own links" ON public.parent_student FOR SELECT TO authenticated
  USING (parent_user_id = auth.uid() OR public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor'));
CREATE POLICY "Staff manage parent links" ON public.parent_student FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor'));
CREATE INDEX IF NOT EXISTS idx_parent_student_parent ON public.parent_student(parent_user_id);
CREATE INDEX IF NOT EXISTS idx_parent_student_student ON public.parent_student(student_id);
CREATE INDEX IF NOT EXISTS idx_behavior_records_student ON public.behavior_records(student_id);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications(recipient_id);

CREATE TABLE public.grades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_id uuid NOT NULL REFERENCES public.exams(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  score numeric(5,2),
  max_score numeric(5,2) NOT NULL DEFAULT 20,
  remark text,
  entered_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (exam_id, student_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.grades TO authenticated;
GRANT ALL ON public.grades TO service_role;
ALTER TABLE public.grades ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Staff manage grades" ON public.grades FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor') OR public.has_role(auth.uid(), 'teacher'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor') OR public.has_role(auth.uid(), 'teacher'));
CREATE POLICY "Students see own grades" ON public.grades FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.students s WHERE s.id = grades.student_id AND s.user_id = auth.uid()));
CREATE POLICY "Parents see linked children grades" ON public.grades FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.student_id = grades.student_id AND ps.parent_user_id = auth.uid()));
CREATE INDEX idx_grades_exam ON public.grades(exam_id);
CREATE INDEX idx_grades_student ON public.grades(student_id);
CREATE TRIGGER grades_set_updated_at BEFORE UPDATE ON public.grades
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.class_teachers (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL,
  subject text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (class_id, teacher_id, subject)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.class_teachers TO authenticated;
GRANT ALL ON public.class_teachers TO service_role;
ALTER TABLE public.class_teachers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage class_teachers" ON public.class_teachers FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director'));
CREATE POLICY "Staff or self can view class_teachers" ON public.class_teachers FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'director') OR public.has_role(auth.uid(), 'supervisor') OR teacher_id = auth.uid());
CREATE TRIGGER trg_class_teachers_updated_at BEFORE UPDATE ON public.class_teachers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP POLICY IF EXISTS "Authenticated can view sessions" ON public.attendance_sessions;
CREATE POLICY "Scoped session reads" ON public.attendance_sessions FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR teacher_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.class_teachers ct WHERE ct.class_id = attendance_sessions.class_id AND ct.teacher_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.students st WHERE st.class_id = attendance_sessions.class_id AND st.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.parent_student ps JOIN public.students st ON st.id = ps.student_id WHERE ps.parent_user_id = auth.uid() AND st.class_id = attendance_sessions.class_id)
  );

DROP POLICY IF EXISTS "Staff or self can view students" ON public.students;
CREATE POLICY "Staff or self can view students" ON public.students FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR public.has_role(auth.uid(), 'gate_monitor')
    OR user_id = auth.uid()
    OR (public.has_role(auth.uid(), 'teacher') AND EXISTS (SELECT 1 FROM public.class_teachers ct WHERE ct.teacher_id = auth.uid() AND ct.class_id = students.class_id))
    OR EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.parent_user_id = auth.uid() AND ps.student_id = students.id)
  );

DROP POLICY IF EXISTS "Staff or self can view attendance" ON public.attendance_records;
CREATE POLICY "Staff or self can view attendance" ON public.attendance_records FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'director')
    OR public.has_role(auth.uid(), 'supervisor')
    OR (public.has_role(auth.uid(), 'teacher') AND EXISTS (SELECT 1 FROM public.attendance_sessions s WHERE s.id = attendance_records.session_id AND s.teacher_id = auth.uid()))
    OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = attendance_records.student_id AND s.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.student_id = attendance_records.student_id AND ps.parent_user_id = auth.uid())
  );

CREATE TABLE public.profile_audit_log (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  details JSONB,
  ip TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX profile_audit_log_user_id_idx ON public.profile_audit_log(user_id, created_at DESC);
GRANT SELECT, INSERT ON public.profile_audit_log TO authenticated;
GRANT ALL ON public.profile_audit_log TO service_role;
ALTER TABLE public.profile_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own audit rows" ON public.profile_audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users read own audit rows" ON public.profile_audit_log FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins read all audit rows" ON public.profile_audit_log FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Users read own avatar or staff read all" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'avatars' AND ((storage.foldername(name))[1] = auth.uid()::text OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor')));
CREATE POLICY "Users can upload to own avatar folder" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Users can update own avatar" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Users can delete own avatar" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
;
-- >>> 20260925093739_9a2a6faa-1c74-4e0f-8b14-7796871d938e.sql
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'developer';
;
-- >>> 20260925093858_6f29572c-f428-47a8-b9a4-39e6bf76da9c.sql
-- Parents: children attendance & behavior
CREATE POLICY "Parents can view linked children behavior" ON public.behavior_records FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.parent_user_id = auth.uid() AND ps.student_id = behavior_records.student_id));

-- Teacher-scoped grade writes
DROP POLICY IF EXISTS "Staff manage grades" ON public.grades;
CREATE POLICY "Management manage grades" ON public.grades FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE POLICY "Teachers manage grades for their classes" ON public.grades FOR ALL TO authenticated
  USING (
    public.has_role(auth.uid(),'teacher') AND EXISTS (
      SELECT 1 FROM public.exams e
      JOIN public.class_teachers ct ON ct.class_id = e.class_id AND ct.teacher_id = auth.uid()
      JOIN public.students s ON s.id = grades.student_id AND s.class_id = e.class_id
      WHERE e.id = grades.exam_id)
  )
  WITH CHECK (
    public.has_role(auth.uid(),'teacher') AND EXISTS (
      SELECT 1 FROM public.exams e
      JOIN public.class_teachers ct ON ct.class_id = e.class_id AND ct.teacher_id = auth.uid()
      JOIN public.students s ON s.id = grades.student_id AND s.class_id = e.class_id
      WHERE e.id = grades.exam_id)
  );

-- Overview stats: management only
CREATE OR REPLACE FUNCTION public.get_overview_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = '28000';
  END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::app_role)
    OR public.has_role(auth.uid(), 'director'::app_role)
    OR public.has_role(auth.uid(), 'supervisor'::app_role)
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'students', (SELECT count(*) FROM public.students),
    'cards', (SELECT count(*) FROM public.rfid_cards),
    'attendance', (SELECT count(*) FROM public.attendance_records),
    'notifications', (SELECT count(*) FROM public.notifications),
    'classes', (SELECT count(*) FROM public.classes),
    'scans', (SELECT count(*) FROM public.card_scans)
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_overview_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_overview_stats() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_user_roles(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_roles(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.prevent_late_override() FROM anon, authenticated, public;

-- Tighter read scopes
DROP POLICY IF EXISTS "Anyone authenticated can view classes" ON public.classes;
CREATE POLICY "Staff and teachers can view classes" ON public.classes FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.exams;
CREATE POLICY "Staff and teachers can view exams" ON public.exams FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.library_items;
CREATE POLICY "Staff and teachers can view library items" ON public.library_items FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.school_decisions;
CREATE POLICY "Staff and teachers can view school decisions" ON public.school_decisions FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
DROP POLICY IF EXISTS "Authenticated can view school admin data" ON public.school_trips;
CREATE POLICY "Staff and teachers can view school trips" ON public.school_trips FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));

-- Owner whitelist
INSERT INTO public.staff_whitelist (email, full_name, role, note)
VALUES
  ('boukaachey@gmail.com', 'Owner (boukaachey)', 'admin', 'Site owner'),
  ('boukaacheyounes@gmail.com', 'Owner (boukaacheyounes)', 'admin', 'Site owner')
ON CONFLICT (full_name) DO UPDATE
  SET email = EXCLUDED.email, role = 'admin', note = EXCLUDED.note;

-- Appearance settings
CREATE OR REPLACE FUNCTION public.set_appearance_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;
REVOKE ALL ON FUNCTION public.set_appearance_updated_at() FROM PUBLIC, anon, authenticated;

CREATE TABLE public.appearance_settings (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  is_global BOOLEAN NOT NULL DEFAULT false,
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX appearance_settings_user_key ON public.appearance_settings (user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX appearance_settings_global_key ON public.appearance_settings ((is_global)) WHERE is_global;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.appearance_settings TO authenticated;
GRANT ALL ON public.appearance_settings TO service_role;
ALTER TABLE public.appearance_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Signed-in users can read appearance settings" ON public.appearance_settings FOR SELECT TO authenticated
  USING (is_global OR user_id = auth.uid());
CREATE POLICY "Users manage their own appearance" ON public.appearance_settings FOR ALL TO authenticated
  USING (user_id = auth.uid() AND NOT is_global) WITH CHECK (user_id = auth.uid() AND NOT is_global);
CREATE POLICY "Admins manage the shared appearance" ON public.appearance_settings FOR ALL TO authenticated
  USING (is_global AND public.has_role(auth.uid(), 'admin')) WITH CHECK (is_global AND public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER appearance_settings_updated_at BEFORE UPDATE ON public.appearance_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_appearance_updated_at();

-- Schedule slots
CREATE TABLE public.schedule_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject text NOT NULL,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time time NOT NULL,
  end_time time NOT NULL,
  room text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.schedule_slots TO authenticated;
GRANT ALL ON public.schedule_slots TO service_role;
ALTER TABLE public.schedule_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "schedule read" ON public.schedule_slots FOR SELECT TO authenticated USING (true);
CREATE POLICY "schedule write" ON public.schedule_slots FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
CREATE TRIGGER trg_schedule_slots_updated_at BEFORE UPDATE ON public.schedule_slots FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_schedule_slots_class ON public.schedule_slots(class_id, weekday, start_time);

-- Homework
CREATE TABLE public.homework (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  teacher_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  subject text NOT NULL,
  title text NOT NULL,
  description text,
  due_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.homework TO authenticated;
GRANT ALL ON public.homework TO service_role;
ALTER TABLE public.homework ENABLE ROW LEVEL SECURITY;
CREATE POLICY "homework read" ON public.homework FOR SELECT TO authenticated USING (true);
CREATE POLICY "homework write" ON public.homework FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor') OR public.has_role(auth.uid(),'teacher'));
CREATE TRIGGER trg_homework_updated_at BEFORE UPDATE ON public.homework FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_homework_class_due ON public.homework(class_id, due_date DESC);

-- Student goals
CREATE TABLE public.student_goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  progress smallint NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  target_date date,
  done boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.student_goals TO authenticated;
GRANT ALL ON public.student_goals TO service_role;
ALTER TABLE public.student_goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "goals owner all" ON public.student_goals FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid()));
CREATE POLICY "goals staff read" ON public.student_goals FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_student_goals_updated_at BEFORE UPDATE ON public.student_goals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_student_goals_student ON public.student_goals(student_id);

-- Absence justifications
CREATE TABLE public.absence_justifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  record_id uuid REFERENCES public.attendance_records(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  absence_date date,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.absence_justifications TO authenticated;
GRANT ALL ON public.absence_justifications TO service_role;
ALTER TABLE public.absence_justifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "justif owner read" ON public.absence_justifications FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.student_id = absence_justifications.student_id AND ps.parent_user_id = auth.uid()));
CREATE POLICY "justif owner insert" ON public.absence_justifications FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.student_id = absence_justifications.student_id AND ps.parent_user_id = auth.uid()));
CREATE POLICY "justif staff all" ON public.absence_justifications FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_absence_justifications_updated_at BEFORE UPDATE ON public.absence_justifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_absence_justifications_student ON public.absence_justifications(student_id, created_at DESC);

-- Parent meeting requests
CREATE TABLE public.meeting_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  preferred_date date,
  preferred_slot text,
  message text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','done')),
  review_note text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meeting_requests TO authenticated;
GRANT ALL ON public.meeting_requests TO service_role;
ALTER TABLE public.meeting_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Parents read own meeting requests" ON public.meeting_requests FOR SELECT TO authenticated
  USING (parent_user_id = auth.uid());
CREATE POLICY "Parents create meeting requests" ON public.meeting_requests FOR INSERT TO authenticated
  WITH CHECK (parent_user_id = auth.uid() AND EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.parent_user_id = auth.uid() AND ps.student_id = meeting_requests.student_id));
CREATE POLICY "Staff manage meeting requests" ON public.meeting_requests FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'director') OR public.has_role(auth.uid(),'supervisor'));
CREATE TRIGGER trg_meeting_requests_updated_at BEFORE UPDATE ON public.meeting_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_meeting_requests_parent ON public.meeting_requests(parent_user_id, created_at DESC);

ALTER TABLE public.schedule_slots REPLICA IDENTITY FULL;
ALTER TABLE public.homework REPLICA IDENTITY FULL;
ALTER TABLE public.meeting_requests REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.schedule_slots;
ALTER PUBLICATION supabase_realtime ADD TABLE public.homework;
ALTER PUBLICATION supabase_realtime ADD TABLE public.meeting_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.student_goals;
ALTER PUBLICATION supabase_realtime ADD TABLE public.absence_justifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.grades;
ALTER PUBLICATION supabase_realtime ADD TABLE public.parent_student;
;
-- >>> 20260927074735_23d940bb-659e-4060-b87c-b0434ef24246.sql
-- 1) أي أستاذ يقرأ كل جلسات الحضور (استخلاف / حصة إضافية / متابعة)
DROP POLICY IF EXISTS "Scoped session reads" ON public.attendance_sessions;
CREATE POLICY "Scoped session reads" ON public.attendance_sessions
FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(), 'admin'::app_role)
  OR public.has_role(auth.uid(), 'director'::app_role)
  OR public.has_role(auth.uid(), 'supervisor'::app_role)
  OR public.has_role(auth.uid(), 'teacher'::app_role)
  OR EXISTS (SELECT 1 FROM public.students st WHERE st.class_id = attendance_sessions.class_id AND st.user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.parent_student ps JOIN public.students st ON st.id = ps.student_id WHERE ps.parent_user_id = auth.uid() AND st.class_id = attendance_sessions.class_id)
);

-- 2) أي أستاذ يقرأ كل سجلات الحضور
DROP POLICY IF EXISTS "Staff or self can view attendance" ON public.attendance_records;
CREATE POLICY "Staff or self can view attendance" ON public.attendance_records
FOR SELECT TO authenticated
USING (
  public.has_role(auth.uid(), 'admin'::app_role)
  OR public.has_role(auth.uid(), 'director'::app_role)
  OR public.has_role(auth.uid(), 'supervisor'::app_role)
  OR public.has_role(auth.uid(), 'teacher'::app_role)
  OR EXISTS (SELECT 1 FROM public.students s WHERE s.id = attendance_records.student_id AND s.user_id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.parent_student ps WHERE ps.student_id = attendance_records.student_id AND ps.parent_user_id = auth.uid())
);

-- 3) تصحيح الخطأ: الأستاذ والطاقم يستطيعون تغيير حالة "متأخر" مباشرة بدون تبرير مسبق
CREATE OR REPLACE FUNCTION public.prevent_late_override()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.status = 'late'
     AND NEW.status <> 'late'
     AND OLD.justified_at IS NULL
     AND NEW.justified_at IS NULL
     AND NOT (
       public.has_role(auth.uid(), 'admin'::app_role)
       OR public.has_role(auth.uid(), 'director'::app_role)
       OR public.has_role(auth.uid(), 'supervisor'::app_role)
       OR public.has_role(auth.uid(), 'teacher'::app_role)
     ) THEN
    RAISE EXCEPTION 'LATE_NOT_JUSTIFIED: لا يمكن تعديل حالة الطالب من "متأخر" قبل تبرير التأخر.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;
;
-- >>> 20260927080506_0c341cfc-abbd-4043-af9e-f974e3bab11d.sql
ALTER TABLE public.schedule_slots
  ADD COLUMN IF NOT EXISTS period_no smallint,
  ADD COLUMN IF NOT EXISTS group_label text NOT NULL DEFAULT 'all',
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_schedule_teacher_day ON public.schedule_slots(teacher_id, weekday);
CREATE INDEX IF NOT EXISTS idx_schedule_class_day ON public.schedule_slots(class_id, weekday);

CREATE OR REPLACE FUNCTION public.check_schedule_conflict()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c record;
BEGIN
  IF NEW.end_time <= NEW.start_time THEN
    RAISE EXCEPTION 'SCHED_BAD_TIME: وقت النهاية يجب أن يكون بعد البداية' USING ERRCODE='check_violation';
  END IF;
  IF NEW.weekday < 0 OR NEW.weekday > 6 THEN
    RAISE EXCEPTION 'SCHED_BAD_DAY' USING ERRCODE='check_violation';
  END IF;
  IF NOT NEW.is_active THEN RETURN NEW; END IF;

  IF NEW.teacher_id IS NOT NULL THEN
    SELECT s.*, cl.name AS cname INTO c FROM schedule_slots s JOIN classes cl ON cl.id=s.class_id
     WHERE s.id <> NEW.id AND s.is_active AND s.teacher_id = NEW.teacher_id AND s.weekday = NEW.weekday
       AND s.start_time < NEW.end_time AND NEW.start_time < s.end_time LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'SCHED_TEACHER_CONFLICT: الأستاذ مبرمج في نفس الوقت مع قسم % (% - %)', c.cname, c.start_time, c.end_time USING ERRCODE='check_violation';
    END IF;
  END IF;

  SELECT s.* INTO c FROM schedule_slots s
   WHERE s.id <> NEW.id AND s.is_active AND s.class_id = NEW.class_id AND s.weekday = NEW.weekday
     AND s.start_time < NEW.end_time AND NEW.start_time < s.end_time
     AND (s.group_label = 'all' OR NEW.group_label = 'all' OR s.group_label = NEW.group_label) LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'SCHED_CLASS_CONFLICT: القسم لديه حصة % في نفس الوقت (% - %)', c.subject, c.start_time, c.end_time USING ERRCODE='check_violation';
  END IF;

  IF NEW.room IS NOT NULL AND btrim(NEW.room) <> '' THEN
    SELECT s.*, cl.name AS cname INTO c FROM schedule_slots s JOIN classes cl ON cl.id=s.class_id
     WHERE s.id <> NEW.id AND s.is_active AND lower(btrim(s.room)) = lower(btrim(NEW.room)) AND s.weekday = NEW.weekday
       AND s.start_time < NEW.end_time AND NEW.start_time < s.end_time LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'SCHED_ROOM_CONFLICT: القاعة محجوزة لقسم % (% - %)', c.cname, c.start_time, c.end_time USING ERRCODE='check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.check_schedule_conflict() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trg_schedule_conflict ON public.schedule_slots;
CREATE TRIGGER trg_schedule_conflict BEFORE INSERT OR UPDATE ON public.schedule_slots
FOR EACH ROW EXECUTE FUNCTION public.check_schedule_conflict();

DROP POLICY IF EXISTS "schedule read" ON public.schedule_slots;
DROP POLICY IF EXISTS "schedule write" ON public.schedule_slots;
REVOKE ALL ON public.schedule_slots FROM anon;
CREATE POLICY "schedule read" ON public.schedule_slots FOR SELECT TO authenticated USING (true);
CREATE POLICY "schedule management write" ON public.schedule_slots FOR ALL TO authenticated
USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'developer'))
WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor') OR has_role(auth.uid(),'developer'));

ALTER TABLE public.attendance_sessions
  ADD COLUMN IF NOT EXISTS slot_id uuid REFERENCES public.schedule_slots(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS session_type text NOT NULL DEFAULT 'regular';
ALTER TABLE public.attendance_sessions DROP CONSTRAINT IF EXISTS attendance_sessions_type_chk;
ALTER TABLE public.attendance_sessions ADD CONSTRAINT attendance_sessions_type_chk CHECK (session_type IN ('regular','replacement','extra'));

CREATE OR REPLACE FUNCTION public.list_teachers()
RETURNS TABLE(id uuid, full_name text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, COALESCE(p.full_name, '—') FROM profiles p
  JOIN user_roles r ON r.user_id = p.id AND r.role = 'teacher'
  WHERE has_role(auth.uid(),'admin') OR has_role(auth.uid(),'director') OR has_role(auth.uid(),'supervisor')
     OR has_role(auth.uid(),'teacher') OR has_role(auth.uid(),'developer')
  ORDER BY 2
$$;
REVOKE EXECUTE ON FUNCTION public.list_teachers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_teachers() TO authenticated;
;
-- >>> 20260927080517_04bf3603-d444-4373-bc63-00e31103d161.sql
REVOKE EXECUTE ON FUNCTION public.check_schedule_conflict() FROM authenticated;
;
-- >>> 20261001165141_d287c008-7ee4-4d62-b24b-b6023436071e.sql
CREATE TABLE public.role_permissions (
  role app_role NOT NULL,
  permission text NOT NULL,
  allowed boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  PRIMARY KEY (role, permission)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.role_permissions TO authenticated;
GRANT ALL ON public.role_permissions TO service_role;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "perm read" ON public.role_permissions FOR SELECT TO authenticated USING (true);
CREATE POLICY "perm admin write" ON public.role_permissions FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'developer'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'developer'));

CREATE TABLE public.user_permission_overrides (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission text NOT NULL,
  allowed boolean NOT NULL,
  note text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  PRIMARY KEY (user_id, permission)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_permission_overrides TO authenticated;
GRANT ALL ON public.user_permission_overrides TO service_role;
ALTER TABLE public.user_permission_overrides ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ovr read" ON public.user_permission_overrides FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR has_role(auth.uid(),'admin') OR has_role(auth.uid(),'developer'));
CREATE POLICY "ovr admin write" ON public.user_permission_overrides FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'developer'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'developer'));

CREATE TABLE public.access_settings (
  key text PRIMARY KEY,
  value numeric NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.access_settings TO authenticated;
GRANT ALL ON public.access_settings TO service_role;
ALTER TABLE public.access_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "acs read" ON public.access_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY "acs admin write" ON public.access_settings FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'developer'))
  WITH CHECK (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'developer'));

INSERT INTO public.access_settings(key, value) VALUES
  ('attendance_edit_window_hours', 0),
  ('attendance_backdate_days', 7);

-- Defaults
INSERT INTO public.role_permissions(role, permission, allowed)
SELECT r::app_role, p, true FROM (VALUES
  ('teacher','attendance.take'),('teacher','attendance.replacement'),('teacher','attendance.extra'),
  ('teacher','attendance.edit_after_save'),('teacher','attendance.override_late'),
  ('teacher','attendance.view_all_classes'),('teacher','homework.manage'),('teacher','notifications.send'),
  ('teacher','schedule.view_all'),
  ('supervisor','attendance.take'),('supervisor','attendance.justify'),('supervisor','attendance.delete_session'),
  ('supervisor','behavior.manage'),('supervisor','notifications.send'),('supervisor','reports.export'),
  ('supervisor','students.manage'),('supervisor','meetings.review'),
  ('director','attendance.justify'),('director','attendance.delete_session'),('director','reports.export'),
  ('director','schedule.manage'),('director','students.manage'),('director','notifications.send'),
  ('director','behavior.manage'),('director','meetings.review'),('director','classes.manage'),
  ('parent','justification.submit'),('parent','meetings.request'),
  ('student','justification.submit')
) v(r,p);

CREATE OR REPLACE FUNCTION public.has_permission(_user_id uuid, _perm text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN _user_id IS NULL THEN false
    WHEN has_role(_user_id,'developer') OR has_role(_user_id,'admin') THEN true
    WHEN EXISTS (SELECT 1 FROM user_permission_overrides o WHERE o.user_id=_user_id AND o.permission=_perm)
      THEN (SELECT o.allowed FROM user_permission_overrides o WHERE o.user_id=_user_id AND o.permission=_perm)
    ELSE COALESCE((SELECT bool_or(rp.allowed) FROM role_permissions rp
                   JOIN user_roles ur ON ur.role = rp.role
                   WHERE ur.user_id=_user_id AND rp.permission=_perm), false)
  END
$$;
GRANT EXECUTE ON FUNCTION public.has_permission(uuid, text) TO authenticated, service_role;

-- Management (admin/director/supervisor) is exempt from teacher attendance limits
CREATE OR REPLACE FUNCTION public.is_management(_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT has_role(_uid,'admin') OR has_role(_uid,'director') OR has_role(_uid,'supervisor') OR has_role(_uid,'developer')
$$;
GRANT EXECUTE ON FUNCTION public.is_management(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enforce_session_permissions()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); win numeric; back numeric; ref record;
BEGIN
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
  -- UPDATE
  IF NOT has_permission(uid,'attendance.edit_after_save') THEN
    RAISE EXCEPTION 'PERM_DENIED: تعديل الحضور بعد الحفظ غير مسموح لحسابك' USING ERRCODE='42501'; END IF;
  SELECT value INTO win FROM access_settings WHERE key='attendance_edit_window_hours';
  IF win IS NOT NULL AND win > 0 AND OLD.created_at < now() - make_interval(hours => win::int) THEN
    RAISE EXCEPTION 'PERM_DENIED: انتهت المدة المسموحة للتعديل (% ساعة)', win::int USING ERRCODE='42501'; END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.enforce_session_permissions() FROM PUBLIC, authenticated;
CREATE TRIGGER trg_session_perms BEFORE INSERT OR UPDATE OR DELETE ON public.attendance_sessions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_session_permissions();

CREATE OR REPLACE FUNCTION public.enforce_record_permissions()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); win numeric; s_created timestamptz;
BEGIN
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
END $$;
REVOKE EXECUTE ON FUNCTION public.enforce_record_permissions() FROM PUBLIC, authenticated;
CREATE TRIGGER trg_record_perms BEFORE INSERT OR UPDATE OR DELETE ON public.attendance_records
  FOR EACH ROW EXECUTE FUNCTION public.enforce_record_permissions();
;
-- >>> 20261002103548_32b462ef-71b5-47dc-b5f9-6e43f222a222.sql
REVOKE EXECUTE ON FUNCTION public.has_permission(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_management(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.enforce_session_permissions() FROM anon;
REVOKE EXECUTE ON FUNCTION public.enforce_record_permissions() FROM anon;
GRANT EXECUTE ON FUNCTION public.has_permission(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_management(uuid) TO authenticated, service_role;
;
-- >>> original 0000
-- The content of this migration cannot be applied: it was copied from the original project and its changes already exist in this database.
-- CREATE TABLE public.substitution_requests (
--   id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
--   requester_id uuid NOT NULL DEFAULT auth.uid(),
--   slot_id uuid REFERENCES public.schedule_slots(id) ON DELETE SET NULL,
--   class_id uuid REFERENCES public.classes(id) ON DELETE CASCADE,
--   request_date date NOT NULL,
--   substitute_teacher_id uuid,
--   reason text NOT NULL,
--   status text NOT NULL DEFAULT 'pending',
--   review_note text,
--   reviewed_by uuid,
--   reviewed_at timestamptz,
--   created_at timestamptz NOT NULL DEFAULT now(),
--   updated_at timestamptz NOT NULL DEFAULT now()
-- );
-- GRANT SELECT, INSERT, UPDATE, DELETE ON public.substitution_requests TO authenticated;
-- GRANT ALL ON public.substitution_requests TO service_role;
-- ALTER TABLE public.substitution_requests ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "sub read" ON public.substitution_requests FOR SELECT TO authenticated
--   USING (requester_id = auth.uid() OR substitute_teacher_id = auth.uid() OR public.is_management(auth.uid()));
-- CREATE POLICY "sub insert" ON public.substitution_requests FOR INSERT TO authenticated
--   WITH CHECK (requester_id = auth.uid() AND status = 'pending');
-- CREATE POLICY "sub cancel own" ON public.substitution_requests FOR DELETE TO authenticated
--   USING ((requester_id = auth.uid() AND status = 'pending') OR public.is_management(auth.uid()));
-- CREATE POLICY "sub review" ON public.substitution_requests FOR UPDATE TO authenticated
--   USING (public.is_management(auth.uid())) WITH CHECK (public.is_management(auth.uid()));
-- CREATE TRIGGER trg_sub_updated BEFORE UPDATE ON public.substitution_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
-- 
-- CREATE TABLE public.school_events (
--   id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
--   title text NOT NULL,
--   event_type text NOT NULL DEFAULT 'event',
--   starts_on date NOT NULL,
--   ends_on date,
--   description text,
--   audience text NOT NULL DEFAULT 'all',
--   created_by uuid DEFAULT auth.uid(),
--   created_at timestamptz NOT NULL DEFAULT now(),
--   updated_at timestamptz NOT NULL DEFAULT now()
-- );
-- GRANT SELECT, INSERT, UPDATE, DELETE ON public.school_events TO authenticated;
-- GRANT ALL ON public.school_events TO service_role;
-- ALTER TABLE public.school_events ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "events read" ON public.school_events FOR SELECT TO authenticated USING (
--   public.is_management(auth.uid()) OR audience = 'all'
--   OR (audience = 'staff' AND public.has_role(auth.uid(),'teacher'))
--   OR (audience = 'families' AND (public.has_role(auth.uid(),'parent') OR public.has_role(auth.uid(),'student'))));
-- CREATE POLICY "events manage" ON public.school_events FOR ALL TO authenticated
--   USING (public.is_management(auth.uid())) WITH CHECK (public.is_management(auth.uid()));
-- CREATE TRIGGER trg_events_updated BEFORE UPDATE ON public.school_events FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
-- 
-- CREATE OR REPLACE FUNCTION public.send_bulk_notification(_target text, _class_id uuid, _title text, _body text)
-- RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
-- DECLARE n integer; lbl text;
-- BEGIN
--   IF NOT public.is_management(auth.uid()) AND NOT public.has_permission(auth.uid(),'notifications.send') THEN
--     RAISE EXCEPTION 'PERM_DENIED' USING ERRCODE='42501';
--   END IF;
--   IF coalesce(btrim(_title),'') = '' THEN RAISE EXCEPTION 'TITLE_REQUIRED'; END IF;
--   lbl := CASE _target WHEN 'teachers' THEN 'كل الأساتذة' WHEN 'parents' THEN 'كل الأولياء'
--     WHEN 'students' THEN 'كل التلاميذ' WHEN 'everyone' THEN 'الجميع'
--     WHEN 'class_parents' THEN 'أولياء قسم' WHEN 'class_students' THEN 'تلاميذ قسم' ELSE NULL END;
--   IF lbl IS NULL THEN RAISE EXCEPTION 'BAD_TARGET'; END IF;
--   IF _target LIKE 'class_%' AND _class_id IS NULL THEN RAISE EXCEPTION 'CLASS_REQUIRED'; END IF;
--   IF _target LIKE 'class_%' THEN lbl := lbl || ' ' || coalesce((SELECT name FROM classes WHERE id=_class_id),''); END IF;
-- 
--   INSERT INTO notifications (recipient_id, recipient_label, title, body, channel, status, created_by)
--   SELECT DISTINCT r.uid, lbl, btrim(_title), nullif(btrim(_body),''), 'inapp', 'sent', auth.uid() FROM (
--     SELECT user_id AS uid FROM user_roles WHERE _target='teachers' AND role='teacher'
--     UNION SELECT user_id FROM user_roles WHERE _target='parents' AND role='parent'
--     UNION SELECT user_id FROM user_roles WHERE _target='students' AND role='student'
--     UNION SELECT user_id FROM user_roles WHERE _target='everyone'
--     UNION SELECT ps.parent_user_id FROM parent_student ps JOIN students s ON s.id=ps.student_id
--       WHERE _target='class_parents' AND s.class_id=_class_id
--     UNION SELECT s.user_id FROM students s WHERE _target='class_students' AND s.class_id=_class_id AND s.user_id IS NOT NULL
--   ) r WHERE r.uid IS NOT NULL;
--   GET DIAGNOSTICS n = ROW_COUNT;
--   RETURN n;
-- END $$;
-- REVOKE ALL ON FUNCTION public.send_bulk_notification(text,uuid,text,text) FROM public, anon;
-- GRANT EXECUTE ON FUNCTION public.send_bulk_notification(text,uuid,text,text) TO authenticated;