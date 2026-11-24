CREATE TABLE public.account_claim_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  kind text NOT NULL CHECK (kind IN ('student','teacher')),
  student_id uuid REFERENCES public.students(id),
  teacher_code text REFERENCES public.teacher_directory(code),
  status text NOT NULL DEFAULT 'valid' CHECK (status IN ('valid','used','revoked')),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '60 days',
  used_at timestamptz,
  claimed_by uuid,
  issued_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind='student' AND student_id IS NOT NULL) OR (kind='teacher' AND teacher_code IS NOT NULL))
);
CREATE UNIQUE INDEX account_claim_one_valid_student ON public.account_claim_tokens(student_id) WHERE status='valid' AND student_id IS NOT NULL;
CREATE UNIQUE INDEX account_claim_one_valid_teacher ON public.account_claim_tokens(teacher_code) WHERE status='valid' AND teacher_code IS NOT NULL;
GRANT SELECT ON public.account_claim_tokens TO authenticated;
GRANT ALL ON public.account_claim_tokens TO service_role;
ALTER TABLE public.account_claim_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "management reads claim tokens" ON public.account_claim_tokens FOR SELECT TO authenticated USING (public.is_management(auth.uid()) OR public.has_role(auth.uid(),'developer'));

CREATE TABLE public.claim_attempts (
  user_id uuid PRIMARY KEY,
  failed_count integer NOT NULL DEFAULT 0,
  locked_until timestamptz
);
GRANT ALL ON public.claim_attempts TO service_role;
ALTER TABLE public.claim_attempts ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.gen_claim_code() RETURNS text LANGUAGE plpgsql VOLATILE SET search_path=public AS $$
DECLARE a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; s text := ''; i int;
BEGIN
  FOR i IN 1..8 LOOP s := s || substr(a, 1 + floor(random()*32)::int, 1); END LOOP;
  RETURN 'TAYM-' || substr(s,1,4) || '-' || substr(s,5,4);
END $$;

CREATE OR REPLACE FUNCTION public.issue_claim_tokens(_kind text, _class uuid DEFAULT NULL) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE n int := 0; r record; c text;
BEGIN
  IF NOT (public.is_management(auth.uid()) OR public.has_role(auth.uid(),'developer')) THEN RAISE EXCEPTION 'مرفوض: للإدارة فقط'; END IF;
  UPDATE account_claim_tokens SET status='revoked' WHERE status='valid' AND expires_at < now();
  IF _kind='student' THEN
    FOR r IN SELECT s.id FROM students s WHERE s.user_id IS NULL AND s.enrollment_status='active'
      AND (_class IS NULL OR s.class_id=_class)
      AND NOT EXISTS (SELECT 1 FROM account_claim_tokens t WHERE t.student_id=s.id AND t.status='valid') LOOP
      LOOP c := gen_claim_code(); EXIT WHEN NOT EXISTS (SELECT 1 FROM account_claim_tokens WHERE code=c); END LOOP;
      INSERT INTO account_claim_tokens(code,kind,student_id,issued_by) VALUES (c,'student',r.id,auth.uid()); n := n+1;
    END LOOP;
  ELSIF _kind='teacher' THEN
    FOR r IN SELECT d.code FROM teacher_directory d WHERE d.user_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM account_claim_tokens t WHERE t.teacher_code=d.code AND t.status='valid') LOOP
      LOOP c := gen_claim_code(); EXIT WHEN NOT EXISTS (SELECT 1 FROM account_claim_tokens WHERE code=c); END LOOP;
      INSERT INTO account_claim_tokens(code,kind,teacher_code,issued_by) VALUES (c,'teacher',r.code,auth.uid()); n := n+1;
    END LOOP;
  ELSE RAISE EXCEPTION 'نوع غير معروف'; END IF;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION public.revoke_claim_token(_id uuid, _reissue boolean DEFAULT false) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t account_claim_tokens; c text;
BEGIN
  IF NOT (public.is_management(auth.uid()) OR public.has_role(auth.uid(),'developer')) THEN RAISE EXCEPTION 'مرفوض: للإدارة فقط'; END IF;
  SELECT * INTO t FROM account_claim_tokens WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'الرمز غير موجود'; END IF;
  IF t.status='used' THEN RAISE EXCEPTION 'الرمز مستعمل مسبقاً'; END IF;
  UPDATE account_claim_tokens SET status='revoked' WHERE id=_id;
  IF NOT _reissue THEN RETURN NULL; END IF;
  LOOP c := gen_claim_code(); EXIT WHEN NOT EXISTS (SELECT 1 FROM account_claim_tokens WHERE code=c); END LOOP;
  INSERT INTO account_claim_tokens(code,kind,student_id,teacher_code,issued_by) VALUES (c,t.kind,t.student_id,t.teacher_code,auth.uid());
  RETURN c;
END $$;

-- Shared lookup with brute-force protection (5 failures => 15 min lock).
CREATE OR REPLACE FUNCTION public.claim_lookup(_code text) RETURNS account_claim_tokens
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t account_claim_tokens; a claim_attempts; uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'سجّل الدخول أولاً'; END IF;
  SELECT * INTO a FROM claim_attempts WHERE user_id=uid;
  IF a.locked_until IS NOT NULL AND a.locked_until > now() THEN RAISE EXCEPTION 'محاولات كثيرة. أعد المحاولة بعد 15 دقيقة'; END IF;
  SELECT * INTO t FROM account_claim_tokens WHERE code=upper(trim(_code));
  IF NOT FOUND OR t.status<>'valid' OR t.expires_at < now() THEN
    INSERT INTO claim_attempts(user_id,failed_count) VALUES (uid,1)
      ON CONFLICT (user_id) DO UPDATE SET failed_count = CASE WHEN claim_attempts.locked_until < now() THEN 1 ELSE claim_attempts.failed_count+1 END,
        locked_until = CASE WHEN claim_attempts.failed_count+1 >= 5 THEN now()+interval '15 minutes' ELSE NULL END;
    RETURN NULL;
  END IF;
  RETURN t;
END $$;

CREATE OR REPLACE FUNCTION public.preview_claim_token(_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t account_claim_tokens; j jsonb;
BEGIN
  t := claim_lookup(_code);
  IF t.id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','الرمز غير صالح أو منتهي أو مستعمل'); END IF;
  IF t.kind='student' THEN
    SELECT jsonb_build_object('ok',true,'kind','student','name',s.full_name,'detail',coalesce(c.name,'')) INTO j
      FROM students s LEFT JOIN classes c ON c.id=s.class_id WHERE s.id=t.student_id;
  ELSE
    SELECT jsonb_build_object('ok',true,'kind','teacher','name',d.full_name,'detail',d.subject) INTO j FROM teacher_directory d WHERE d.code=t.teacher_code;
  END IF;
  RETURN j;
END $$;

CREATE OR REPLACE FUNCTION public.claim_account(_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t account_claim_tokens; uid uuid := auth.uid(); nm text;
BEGIN
  t := claim_lookup(_code);
  IF t.id IS NULL THEN RAISE EXCEPTION 'الرمز غير صالح أو منتهي أو مستعمل'; END IF;
  PERFORM 1 FROM account_claim_tokens WHERE id=t.id AND status='valid' FOR UPDATE;
  IF t.kind='student' THEN
    IF EXISTS (SELECT 1 FROM students WHERE user_id=uid) THEN RAISE EXCEPTION 'حسابك مرتبط مسبقاً بتلميذ'; END IF;
    IF EXISTS (SELECT 1 FROM teacher_directory WHERE user_id=uid) THEN RAISE EXCEPTION 'هذا الحساب حساب أستاذ'; END IF;
    UPDATE students SET user_id=uid WHERE id=t.student_id AND user_id IS NULL RETURNING full_name INTO nm;
    IF nm IS NULL THEN RAISE EXCEPTION 'هذا التلميذ مرتبط بحساب آخر'; END IF;
    INSERT INTO user_roles(user_id,role) VALUES (uid,'student') ON CONFLICT DO NOTHING;
  ELSE
    IF EXISTS (SELECT 1 FROM students WHERE user_id=uid) THEN RAISE EXCEPTION 'هذا الحساب مرتبط بتلميذ'; END IF;
    UPDATE teacher_directory SET user_id=uid, updated_at=now() WHERE code=t.teacher_code AND user_id IS NULL RETURNING full_name INTO nm;
    IF nm IS NULL THEN RAISE EXCEPTION 'هذا الأستاذ مرتبط بحساب آخر'; END IF;
    DELETE FROM user_roles WHERE user_id=uid AND role='student';
    INSERT INTO user_roles(user_id,role) VALUES (uid,'teacher') ON CONFLICT DO NOTHING;
    UPDATE profiles SET full_name=nm, updated_at=now() WHERE id=uid;
  END IF;
  UPDATE account_claim_tokens SET status='used', used_at=now(), claimed_by=uid WHERE id=t.id;
  DELETE FROM claim_attempts WHERE user_id=uid;
  RETURN jsonb_build_object('ok',true,'kind',t.kind,'name',nm);
END $$;

REVOKE ALL ON FUNCTION public.claim_lookup(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gen_claim_code() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.issue_claim_tokens(text,uuid), public.revoke_claim_token(uuid,boolean), public.preview_claim_token(text), public.claim_account(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_claim_tokens(text,uuid), public.revoke_claim_token(uuid,boolean), public.preview_claim_token(text), public.claim_account(text) TO authenticated;