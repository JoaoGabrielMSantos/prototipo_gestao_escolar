/**
 * tenant-isolation.test.ts — automated proof of tenant isolation through
 * the real client path (supabase-js + PostgREST + RLS), complementing the
 * SQL-level proof in supabase/tests/tenant_isolation.sql.
 *
 * These are integration tests: they need a running local stack
 * (`supabase start && supabase db reset`) and the anon key in
 * .env.test.local. They use ONLY the anon key — never the service role,
 * which bypasses RLS and would make the tests meaningless.
 *
 *   npm run test:isolation
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';

const URL = process.env.VITE_SUPABASE_URL!;
const ANON = process.env.VITE_SUPABASE_ANON_KEY!;

const SCHOOL_A = '11111111-1111-1111-1111-111111111111';
const SCHOOL_B = '22222222-2222-2222-2222-222222222222';

/** Signs in a seeded user and returns a client bound to that session. */
async function signIn(email: string): Promise<SupabaseClient> {
  const client = createClient(URL, ANON, { auth: { persistSession: false } });
  const { error } = await client.auth.signInWithPassword({ email, password: 'senha123' });
  if (error) throw new Error(`sign-in failed for ${email}: ${error.message}`);
  return client;
}

let adminA: SupabaseClient;
let adminB: SupabaseClient;
let teacherA: SupabaseClient;
let studentA: SupabaseClient;

beforeAll(async () => {
  [adminA, adminB, teacherA, studentA] = await Promise.all([
    signIn('admin@aurora.test'),
    signIn('admin@bandeirante.test'),
    signIn('prof@aurora.test'),
    signIn('aluno@aurora.test'),
  ]);
});

describe('reads are scoped to the caller tenant', () => {
  it('school A admin cannot see school B classes even when asking for them by id', async () => {
    const { data, error } = await adminA.from('classes').select('*').eq('school_id', SCHOOL_B);
    expect(error).toBeNull();
    // RLS filters rows out silently — an empty result, not a 403.
    expect(data).toEqual([]);
  });

  it('the two admins see disjoint class sets', async () => {
    const [a, b] = await Promise.all([
      adminA.from('classes').select('school_id'),
      adminB.from('classes').select('school_id'),
    ]);
    expect(a.data?.every((r) => r.school_id === SCHOOL_A)).toBe(true);
    expect(b.data?.every((r) => r.school_id === SCHOOL_B)).toBe(true);
  });

  it('school A admin cannot read school B students or grades', async () => {
    const students = await adminA.from('students').select('id').eq('school_id', SCHOOL_B);
    const grades = await adminA.from('grades').select('id').eq('school_id', SCHOOL_B);
    expect(students.data).toEqual([]);
    expect(grades.data).toEqual([]);
  });
});

describe('writes cannot cross the tenant boundary', () => {
  it('rejects an insert carrying another school_id', async () => {
    const { error } = await adminA
      .from('classes')
      .insert({ school_id: SCHOOL_B, name: 'Turma Invasora', year: 2026 });
    // 42501 = insufficient_privilege, raised by the WITH CHECK clause.
    expect(error?.code).toBe('42501');
  });

  it('rejects moving an owned row into another tenant', async () => {
    const { data: own } = await adminA.from('classes').select('id').limit(1).single();
    const { error } = await adminA
      .from('classes')
      .update({ school_id: SCHOOL_B })
      .eq('id', own!.id);
    expect(error?.code).toBe('42501');
  });

  it('updates and deletes targeting another tenant affect nothing', async () => {
    const upd = await adminA
      .from('classes')
      .update({ name: 'renamed by intruder' })
      .eq('school_id', SCHOOL_B)
      .select();
    const del = await adminA.from('classes').delete().eq('school_id', SCHOOL_B).select();
    expect(upd.data).toEqual([]);
    expect(del.data).toEqual([]);
  });
});

describe('role limits inside the tenant', () => {
  it('teacher can read classes but not create them', async () => {
    const read = await teacherA.from('classes').select('id');
    expect(read.data?.length).toBeGreaterThan(0);

    const write = await teacherA
      .from('classes')
      .insert({ school_id: SCHOOL_A, name: 'Turma do Professor', year: 2026 });
    expect(write.error?.code).toBe('42501');
  });

  it('student sees only their own record and grades', async () => {
    const students = await studentA.from('students').select('id');
    const grades = await studentA.from('grades').select('id');
    expect(students.data?.length).toBe(1);
    expect(grades.data?.length).toBe(1);
  });

  it('student cannot escalate their own role', async () => {
    const { data: me } = await studentA.auth.getUser();
    const { data, error } = await studentA
      .from('profiles')
      .update({ role: 'super_admin' })
      .eq('id', me.user!.id)
      .select();
    // Either blocked by WITH CHECK or filtered to zero rows — never applied.
    expect(error?.code === '42501' || data?.length === 0).toBe(true);
  });
});
