-- =====================================================================
-- seed.sql — 2 test schools + one user per role in each.
-- Runs automatically on "supabase db reset" (LOCAL environment only).
--
-- Users are inserted straight into auth.users with metadata; the
-- app.handle_new_user trigger creates the matching profile — the same
-- path a real signup takes. Password for all of them: senha123
-- =====================================================================

insert into public.schools (id, name, slug) values
  ('11111111-1111-1111-1111-111111111111', 'Colégio Aurora',       'aurora'),
  ('22222222-2222-2222-2222-222222222222', 'Instituto Bandeirante', 'bandeirante');

-- Local helper: create an Auth user carrying role/school in metadata.
create or replace function app.seed_user(
  p_id uuid, p_email text, p_role text, p_school uuid, p_name text
) returns void language plpgsql as $$
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  ) values (
    p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    p_email, crypt('senha123', gen_salt('bf')), now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('role', p_role, 'school_id', p_school, 'full_name', p_name)
  );
end;
$$;

select app.seed_user('aaaaaaaa-0000-0000-0000-000000000001', 'owner@plataforma.dev', 'super_admin', null, 'Dono da Plataforma');

-- School A — Colégio Aurora
select app.seed_user('aaaaaaaa-0000-0000-0000-00000000000a', 'admin@aurora.test', 'school_admin', '11111111-1111-1111-1111-111111111111', 'Direção Aurora');
select app.seed_user('aaaaaaaa-0000-0000-0000-00000000000b', 'prof@aurora.test',  'teacher',      '11111111-1111-1111-1111-111111111111', 'Marina Prof. Aurora');
select app.seed_user('aaaaaaaa-0000-0000-0000-00000000000c', 'aluno@aurora.test', 'student',      '11111111-1111-1111-1111-111111111111', 'Ana Aluna Aurora');

-- School B — Instituto Bandeirante
select app.seed_user('bbbbbbbb-0000-0000-0000-00000000000a', 'admin@bandeirante.test', 'school_admin', '22222222-2222-2222-2222-222222222222', 'Direção Bandeirante');
select app.seed_user('bbbbbbbb-0000-0000-0000-00000000000b', 'prof@bandeirante.test',  'teacher',      '22222222-2222-2222-2222-222222222222', 'Caio Prof. Bandeirante');
select app.seed_user('bbbbbbbb-0000-0000-0000-00000000000c', 'aluno@bandeirante.test', 'student',      '22222222-2222-2222-2222-222222222222', 'Bruno Aluno Bandeirante');

-- Structural data for both schools. Class names and subject codes are
-- duplicated across tenants on purpose: they prove uniqueness is
-- scoped per tenant, not global.
insert into public.classes (id, school_id, name, year) values
  ('c1a00000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '9º ano A',  2026),
  ('c1a00000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '1º ano EM', 2026),
  ('c1b00000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', '9º ano A',  2026);

insert into public.subjects (id, school_id, name, code) values
  ('50a00000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Matemática', 'MAT'),
  ('50a00000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'História',   'HIS'),
  ('50b00000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Matemática', 'MAT');

insert into public.students (id, school_id, profile_id, full_name, guardian_name, guardian_phone) values
  ('57a00000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-00000000000c', 'Ana Aluna Aurora', 'Cláudia Aurora', '(11) 90000-0001'),
  ('57a00000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', null, 'Pedro Souza', 'Rita Souza', '(11) 90000-0002'),
  ('57b00000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-00000000000c', 'Bruno Aluno Bandeirante', 'Jorge Bandeira', '(21) 90000-0003');

insert into public.teachers (id, school_id, profile_id, full_name, email) values
  ('7ea00000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-00000000000b', 'Marina Prof. Aurora', 'prof@aurora.test'),
  ('7eb00000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-00000000000b', 'Caio Prof. Bandeirante', 'prof@bandeirante.test');

insert into public.enrollments (school_id, student_id, class_id) values
  ('11111111-1111-1111-1111-111111111111', '57a00000-0000-0000-0000-000000000001', 'c1a00000-0000-0000-0000-000000000001'),
  ('11111111-1111-1111-1111-111111111111', '57a00000-0000-0000-0000-000000000002', 'c1a00000-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222', '57b00000-0000-0000-0000-000000000001', 'c1b00000-0000-0000-0000-000000000001');

insert into public.teacher_assignments (school_id, teacher_id, class_id, subject_id) values
  ('11111111-1111-1111-1111-111111111111', '7ea00000-0000-0000-0000-000000000001', 'c1a00000-0000-0000-0000-000000000001', '50a00000-0000-0000-0000-000000000001'),
  ('22222222-2222-2222-2222-222222222222', '7eb00000-0000-0000-0000-000000000001', 'c1b00000-0000-0000-0000-000000000001', '50b00000-0000-0000-0000-000000000001');

-- Raw grade values, with no period or averaging semantics attached.
insert into public.grades (school_id, student_id, class_id, subject_id, value, date) values
  ('11111111-1111-1111-1111-111111111111', '57a00000-0000-0000-0000-000000000001', 'c1a00000-0000-0000-0000-000000000001', '50a00000-0000-0000-0000-000000000001', 8.50, '2026-03-20'),
  ('22222222-2222-2222-2222-222222222222', '57b00000-0000-0000-0000-000000000001', 'c1b00000-0000-0000-0000-000000000001', '50b00000-0000-0000-0000-000000000001', 7.00, '2026-03-21');

drop function app.seed_user(uuid, text, text, uuid, text);
