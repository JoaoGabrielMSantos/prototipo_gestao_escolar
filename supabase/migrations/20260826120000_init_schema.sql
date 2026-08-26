-- =====================================================================
-- 20260826120000_init_schema.sql
-- Base schema for the multi-tenant school management SaaS.
--
-- ARCHITECTURE DECISION: row-level tenancy (shared schema, shared DB).
-- One Postgres instance serves every school. Every table holding
-- school-scoped data carries school_id, and isolation is enforced by
-- RLS (see 20260826120100_rls_policies.sql).
--
-- Why not schema-per-tenant or database-per-tenant?
--   - Operations: migrations run once instead of N times.
--   - Expected scale is tens/hundreds of schools, not thousands.
--   - Supabase Auth + RLS put the isolation guarantee inside the
--     database, so it does not depend on the application code
--     remembering to add "where school_id = ..." to every query.
-- =====================================================================

create extension if not exists pgcrypto;

-- System roles. super_admin is global (platform owner); every other
-- role only exists inside a school.
create type public.user_role as enum ('super_admin', 'school_admin', 'teacher', 'student');

-- ---------------------------------------------------------------------
-- schools: the tenant table. Root of all isolation.
-- ---------------------------------------------------------------------
create table public.schools (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text not null unique,          -- for future URL/subdomain routing
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- profiles: mirror of auth.users holding the tenant + role binding.
-- auth.users is managed by Supabase Auth and cannot take domain
-- columns, so (school_id, role) lives here. This is the table every
-- RLS policy consults to answer "who is the caller and which school
-- do they belong to?".
-- ---------------------------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  school_id  uuid references public.schools(id) on delete cascade,
  role       public.user_role not null default 'student',
  full_name  text not null default '',
  created_at timestamptz not null default now(),

  -- Model invariant: super_admin belongs to no school; every other
  -- role must belong to exactly one.
  constraint profiles_tenant_scope check (
    (role = 'super_admin' and school_id is null)
    or (role <> 'super_admin' and school_id is not null)
  )
);
create index profiles_school_id_idx on public.profiles (school_id);

-- ---------------------------------------------------------------------
-- Structural school entities.
--
-- Pattern applied to all of them: school_id NOT NULL plus a seemingly
-- redundant unique (id, school_id). That unique key is what allows
-- COMPOSITE FOREIGN KEYS on the join tables below, which makes it
-- impossible at the database level to build a row that mixes tenants
-- (e.g. enrolling a student of school A into a class of school B) —
-- a bug class RLS alone does not catch, since a super_admin can see
-- both rows.
-- ---------------------------------------------------------------------
create table public.classes (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  name       text not null,                 -- e.g. "9º ano B"
  year       int  not null,                 -- calendar year of the class
  created_at timestamptz not null default now(),
  unique (id, school_id),
  unique (school_id, name, year)            -- uniqueness is per tenant
);
create index classes_school_id_idx on public.classes (school_id);

create table public.subjects (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  name       text not null,                 -- e.g. "Matemática"
  code       text not null,                 -- e.g. "MAT"
  created_at timestamptz not null default now(),
  unique (id, school_id),
  unique (school_id, code)
);
create index subjects_school_id_idx on public.subjects (school_id);

-- A student as a person registered at the school. profile_id is
-- optional: the student record exists before (or without ever) having
-- a login.
create table public.students (
  id             uuid primary key default gen_random_uuid(),
  school_id      uuid not null references public.schools(id) on delete cascade,
  profile_id     uuid references public.profiles(id) on delete set null,
  full_name      text not null,
  birth_date     date,
  guardian_name  text,
  guardian_phone text,
  created_at     timestamptz not null default now(),
  unique (id, school_id)
);
create index students_school_id_idx on public.students (school_id);

create table public.teachers (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete set null,
  full_name  text not null,
  email      text,
  created_at timestamptz not null default now(),
  unique (id, school_id)
);
create index teachers_school_id_idx on public.teachers (school_id);

-- ---------------------------------------------------------------------
-- Join tables. Every FK is composite and includes school_id.
-- ---------------------------------------------------------------------

-- Student enrolled in a class.
create table public.enrollments (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references public.schools(id) on delete cascade,
  student_id  uuid not null,
  class_id    uuid not null,
  status      text not null default 'active',   -- active | transferred | inactive
  enrolled_at date not null default current_date,
  created_at  timestamptz not null default now(),
  foreign key (student_id, school_id) references public.students (id, school_id) on delete cascade,
  foreign key (class_id, school_id)   references public.classes  (id, school_id) on delete cascade,
  unique (student_id, class_id)
);
create index enrollments_school_id_idx on public.enrollments (school_id);

-- Teacher teaching a subject to a class.
create table public.teacher_assignments (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  teacher_id uuid not null,
  class_id   uuid not null,
  subject_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (teacher_id, school_id) references public.teachers (id, school_id) on delete cascade,
  foreign key (class_id, school_id)   references public.classes  (id, school_id) on delete cascade,
  foreign key (subject_id, school_id) references public.subjects (id, school_id) on delete cascade,
  unique (teacher_id, class_id, subject_id)
);
create index teacher_assignments_school_id_idx on public.teacher_assignments (school_id);

-- ---------------------------------------------------------------------
-- grades: DELIBERATELY NEUTRAL AND MINIMAL.
--
-- Stores the raw value of a single graded event. What is intentionally
-- NOT here, pending validation with the partner school:
--   - academic period column (bimester / trimester / semester)
--   - assessment type, weight, averaging formula
--   - pass/fail or retake (recuperação) flags
--   - any view, trigger or function that computes an average
-- All of those depend on business rules that are not confirmed yet.
-- The plain `date` column is enough to reconstruct any period model
-- later without hardcoding one now.
-- ---------------------------------------------------------------------
create table public.grades (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null,
  class_id   uuid not null,
  subject_id uuid not null,
  value      numeric(5,2) not null,
  date       date not null default current_date,
  created_at timestamptz not null default now(),
  foreign key (student_id, school_id) references public.students (id, school_id) on delete cascade,
  foreign key (class_id, school_id)   references public.classes  (id, school_id) on delete cascade,
  foreign key (subject_id, school_id) references public.subjects (id, school_id) on delete cascade
);
create index grades_school_id_idx on public.grades (school_id);
create index grades_student_idx   on public.grades (student_id, date);
