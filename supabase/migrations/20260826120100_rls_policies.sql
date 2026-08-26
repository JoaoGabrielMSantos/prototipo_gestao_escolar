-- =====================================================================
-- 20260826120100_rls_policies.sql
-- Row Level Security: the tenant isolation layer.
--
-- MENTAL MODEL
-- Every frontend request reaches Postgres through PostgREST carrying
-- the user's JWT, so auth.uid() returns the caller id. From that id we
-- resolve school_id and role in public.profiles, and every policy
-- collapses into: "does this row belong to MY school?" (plus "does my
-- role allow this action?").
--
-- WHY THE HELPERS BELOW ARE SECURITY DEFINER
-- If a policy on public.profiles selected from public.profiles, that
-- same policy would be re-evaluated => infinite recursion. SECURITY
-- DEFINER functions run with the owner's privileges and bypass RLS,
-- breaking the cycle. They are STABLE so the planner evaluates them
-- once per query instead of once per row.
-- =====================================================================

create schema if not exists app;
grant usage on schema app to authenticated, anon;

-- school_id of the caller (NULL for super_admin).
create or replace function app.current_school_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select school_id from public.profiles where id = auth.uid()
$$;

-- role of the caller.
create or replace function app.current_role()
returns public.user_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function app.is_super_admin()
returns boolean language sql stable
as $$ select app.current_role() = 'super_admin' $$;

create or replace function app.is_school_admin()
returns boolean language sql stable
as $$ select app.current_role() = 'school_admin' $$;

-- "am I a member of this school?" — the predicate reused by every
-- policy. The NULL check matters: without it a super_admin (school_id
-- NULL) would match rows whose school_id is NULL.
create or replace function app.belongs_to_school(target uuid)
returns boolean language sql stable
as $$ select target is not null and target = app.current_school_id() $$;

grant execute on all functions in schema app to authenticated;

-- ---------------------------------------------------------------------
-- Profile provisioning on signup.
-- Role and school come from the Auth user metadata, so there is no code
-- path where an authenticated user ends up without a tenant.
-- ---------------------------------------------------------------------
create or replace function app.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, school_id, role, full_name)
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'school_id', '')::uuid,
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'student'),
    coalesce(new.raw_user_meta_data->>'full_name', '')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- ---------------------------------------------------------------------
-- RLS enabled on EVERY table. A table with RLS on and no policy denies
-- everything (fail closed) — the safe default we want.
-- ---------------------------------------------------------------------
alter table public.schools             enable row level security;
alter table public.profiles            enable row level security;
alter table public.classes             enable row level security;
alter table public.subjects            enable row level security;
alter table public.students            enable row level security;
alter table public.teachers            enable row level security;
alter table public.enrollments         enable row level security;
alter table public.teacher_assignments enable row level security;
alter table public.grades              enable row level security;

-- =====================  schools  =====================================
-- Read: super_admin sees all; a member sees ONLY their own school.
create policy schools_select on public.schools for select to authenticated
using ( app.is_super_admin() or id = app.current_school_id() );

-- Write: super_admin only. Creating/editing a school is a platform
-- action, not a school action.
create policy schools_write on public.schools for all to authenticated
using ( app.is_super_admin() ) with check ( app.is_super_admin() );

-- =====================  profiles  ====================================
create policy profiles_select on public.profiles for select to authenticated
using (
  id = auth.uid()
  or app.is_super_admin()
  or (app.is_school_admin() and app.belongs_to_school(school_id))
);

-- Users may edit their own profile but NOT their role or school_id:
-- that would be privilege escalation / tenant hopping.
create policy profiles_update_self on public.profiles for update to authenticated
using ( id = auth.uid() )
with check (
  id = auth.uid()
  and role = app.current_role()
  and school_id is not distinct from app.current_school_id()
);

create policy profiles_admin_write on public.profiles for all to authenticated
using ( app.is_super_admin() or (app.is_school_admin() and app.belongs_to_school(school_id)) )
with check ( app.is_super_admin() or (app.is_school_admin() and app.belongs_to_school(school_id)) );

-- =====================  classes / subjects  ==========================
-- Read: any authenticated member of the school (teachers and students
-- need to see classes and subjects). Write: school_admin of that school.
--
-- WITH CHECK is what blocks the obvious attack: a school_admin of
-- school A inserting a row with school_id of school B. USING filters
-- what they can see; WITH CHECK validates what they can write. Both
-- are required — USING alone leaves inserts wide open.
create policy classes_select on public.classes for select to authenticated
using ( app.is_super_admin() or app.belongs_to_school(school_id) );

create policy classes_write on public.classes for all to authenticated
using ( app.is_school_admin() and app.belongs_to_school(school_id) )
with check ( app.is_school_admin() and app.belongs_to_school(school_id) );

create policy subjects_select on public.subjects for select to authenticated
using ( app.is_super_admin() or app.belongs_to_school(school_id) );

create policy subjects_write on public.subjects for all to authenticated
using ( app.is_school_admin() and app.belongs_to_school(school_id) )
with check ( app.is_school_admin() and app.belongs_to_school(school_id) );

-- =====================  students  ====================================
-- Personal data of minors: readable by school staff only, plus the
-- student themselves on their own record.
create policy students_select on public.students for select to authenticated
using (
  app.is_super_admin()
  or (app.belongs_to_school(school_id) and app.current_role() in ('school_admin', 'teacher'))
  or profile_id = auth.uid()
);

create policy students_write on public.students for all to authenticated
using ( app.is_school_admin() and app.belongs_to_school(school_id) )
with check ( app.is_school_admin() and app.belongs_to_school(school_id) );

-- =====================  teachers  ====================================
create policy teachers_select on public.teachers for select to authenticated
using ( app.is_super_admin() or app.belongs_to_school(school_id) );

create policy teachers_write on public.teachers for all to authenticated
using ( app.is_school_admin() and app.belongs_to_school(school_id) )
with check ( app.is_school_admin() and app.belongs_to_school(school_id) );

-- =====================  enrollments  =================================
create policy enrollments_select on public.enrollments for select to authenticated
using (
  app.is_super_admin()
  or (app.belongs_to_school(school_id) and app.current_role() in ('school_admin', 'teacher'))
  or exists (
    select 1 from public.students s
    where s.id = enrollments.student_id and s.profile_id = auth.uid()
  )
);

create policy enrollments_write on public.enrollments for all to authenticated
using ( app.is_school_admin() and app.belongs_to_school(school_id) )
with check ( app.is_school_admin() and app.belongs_to_school(school_id) );

-- =====================  teacher_assignments  =========================
create policy teacher_assignments_select on public.teacher_assignments for select to authenticated
using ( app.is_super_admin() or app.belongs_to_school(school_id) );

create policy teacher_assignments_write on public.teacher_assignments for all to authenticated
using ( app.is_school_admin() and app.belongs_to_school(school_id) )
with check ( app.is_school_admin() and app.belongs_to_school(school_id) );

-- =====================  grades  ======================================
-- ACCESS control over the raw value only. No grading logic lives here.
-- Students read their own grades; staff read their own school's.
create policy grades_select on public.grades for select to authenticated
using (
  app.is_super_admin()
  or (app.belongs_to_school(school_id) and app.current_role() in ('school_admin', 'teacher'))
  or exists (
    select 1 from public.students s
    where s.id = grades.student_id and s.profile_id = auth.uid()
  )
);

-- Writing a grade: school_admin or teacher of the same school.
-- Narrowing teachers down to their own classes/subjects depends on the
-- pedagogical rules still under validation, so it is left out on
-- purpose (see docs/HANDOFF.md, "Out of scope").
create policy grades_write on public.grades for all to authenticated
using (
  app.belongs_to_school(school_id)
  and app.current_role() in ('school_admin', 'teacher')
)
with check (
  app.belongs_to_school(school_id)
  and app.current_role() in ('school_admin', 'teacher')
);
