-- Base schema consolidated from the original project's latest full schema snapshot and later changes (fresh database).
-- >>> 20260924171244_4ef2f925-a88a-43e4-a3f8-3ef898c38502.sql
-- Roles enum
CREATE TYPE public.app_role AS ENUM ('admin', 'director', 'supervisor', 'teacher', 'parent', 'student', 'gate_monitor', 'developer', 'class_rep', 'class_rep_deputy');

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