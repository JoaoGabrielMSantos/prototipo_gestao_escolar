-- =====================================================================
-- tenant_isolation.sql — executable proof of tenant isolation.
--
-- Run against the local database (after "supabase db reset"):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--        -f supabase/tests/tenant_isolation.sql
--
-- The script impersonates real users by switching to the authenticated
-- role and injecting the JWT "sub" claim — exactly what PostgREST does
-- on every request. Any failed assertion aborts the script with a
-- non-zero exit code, so it works as a CI gate. Everything runs inside
-- a transaction that is rolled back at the end.
-- =====================================================================

\set ON_ERROR_STOP on

create or replace function app.assert(cond boolean, label text)
returns void language plpgsql as $$
begin
  if cond then raise notice 'PASS  %', label;
  else raise exception 'FAIL  %', label;
  end if;
end;
$$;

-- Impersonate a user: authenticated role + sub claim.
create or replace function app.login_as(p_user uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

begin;

-- ============ CASE 1: reads never cross the tenant boundary ============
select app.login_as('aaaaaaaa-0000-0000-0000-00000000000a'); -- school_admin of school A

select app.assert(
  (select count(*) from public.classes where school_id = '22222222-2222-2222-2222-222222222222') = 0,
  'admin A cannot read classes of school B');

select app.assert(
  (select count(*) from public.students where school_id = '22222222-2222-2222-2222-222222222222') = 0,
  'admin A cannot read students of school B');

select app.assert(
  (select count(*) from public.grades where school_id = '22222222-2222-2222-2222-222222222222') = 0,
  'admin A cannot read grades of school B');

select app.assert(
  (select count(*) from public.schools) = 1,
  'admin A sees only their own school row');

select app.assert(
  (select count(*) from public.classes) = 2,
  'admin A sees the 2 classes of their own school');

-- ============ CASE 2: cross-tenant writes are rejected ============
do $$
begin
  insert into public.classes (school_id, name, year)
  values ('22222222-2222-2222-2222-222222222222', 'Turma Invasora', 2026);
  raise exception 'FAIL  admin A managed to INSERT into school B';
exception
  when insufficient_privilege then raise notice 'PASS  cross-tenant INSERT blocked by WITH CHECK';
end;
$$;

do $$
declare affected int;
begin
  update public.classes set name = 'renamed by intruder'
  where school_id = '22222222-2222-2222-2222-222222222222';
  get diagnostics affected = row_count;
  perform app.assert(affected = 0, 'cross-tenant UPDATE affects zero rows (USING filters first)');
end;
$$;

do $$
declare affected int;
begin
  delete from public.classes where school_id = '22222222-2222-2222-2222-222222222222';
  get diagnostics affected = row_count;
  perform app.assert(affected = 0, 'cross-tenant DELETE affects zero rows');
end;
$$;

-- ============ CASE 3: moving an owned row into another tenant ============
do $$
begin
  update public.classes
     set school_id = '22222222-2222-2222-2222-222222222222'
   where id = 'c1a00000-0000-0000-0000-000000000001';
  raise exception 'FAIL  admin A managed to move a class to school B';
exception
  when insufficient_privilege then raise notice 'PASS  reassigning school_id blocked by WITH CHECK';
end;
$$;

-- ============ CASE 4: role limits inside the caller's own tenant ============
select app.login_as('aaaaaaaa-0000-0000-0000-00000000000b'); -- teacher of school A

select app.assert(
  (select count(*) from public.classes) = 2,
  'teacher reads classes of their own school');

do $$
begin
  insert into public.classes (school_id, name, year)
  values ('11111111-1111-1111-1111-111111111111', 'Turma do Professor', 2026);
  raise exception 'FAIL  teacher managed to create a class';
exception
  when insufficient_privilege then raise notice 'PASS  teacher cannot create classes (school_admin only)';
end;
$$;

-- ============ CASE 5: a student only sees their own data ============
select app.login_as('aaaaaaaa-0000-0000-0000-00000000000c'); -- student of school A

select app.assert(
  (select count(*) from public.students) = 1,
  'student sees only their own record');

select app.assert(
  (select count(*) from public.grades) = 1,
  'student sees only their own grades');

-- ============ CASE 6: privilege escalation ============
do $$
declare affected int;
begin
  update public.profiles set role = 'super_admin' where id = auth.uid();
  get diagnostics affected = row_count;
  raise exception 'FAIL  student escalated to super_admin (% rows)', affected;
exception
  when insufficient_privilege then raise notice 'PASS  student cannot change their own role';
end;
$$;

-- ============ CASE 7: super_admin crosses tenants by design ============
select app.login_as('aaaaaaaa-0000-0000-0000-000000000001');

select app.assert((select count(*) from public.schools) = 2, 'super_admin sees both schools');

rollback;

\echo '== All tenant isolation cases passed =='
