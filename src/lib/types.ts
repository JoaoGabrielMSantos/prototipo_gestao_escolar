/**
 * Domain types. Mirrors the SQL schema.
 *
 * `Database` (src/lib/database.types.ts) is GENERATED — do not hand-edit:
 *   npx supabase gen types typescript --local > src/lib/database.types.ts
 * The aliases below are what application code should import, so that a
 * regenerated file does not ripple through every component.
 */
import type { Database } from './database.types';

type Tables = Database['public']['Tables'];

export type UserRole = Database['public']['Enums']['user_role'];

export type School = Tables['schools']['Row'];
export type Profile = Pick<Tables['profiles']['Row'], 'id' | 'school_id' | 'role' | 'full_name'>;
export type Class = Tables['classes']['Row'];
export type Subject = Tables['subjects']['Row'];
export type Student = Tables['students']['Row'];
export type Teacher = Tables['teachers']['Row'];
export type Enrollment = Tables['enrollments']['Row'];
export type TeacherAssignment = Tables['teacher_assignments']['Row'];

/**
 * Raw grade record. Intentionally has no period, weight or computed
 * average — see the comment block on public.grades in the init migration.
 */
export type Grade = Tables['grades']['Row'];

export const ROLE_LABELS: Record<UserRole, string> = {
  super_admin: 'Administrador da plataforma',
  school_admin: 'Direção',
  teacher: 'Professor',
  student: 'Aluno',
};
