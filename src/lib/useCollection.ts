/**
 * useCollection — the single data-access pattern for every tenant-scoped
 * list screen (classes, subjects, students, teachers).
 *
 * Deliberately thin: no client-side school filter. The caller's school
 * scope is applied by RLS in Postgres, so `select('*')` already returns
 * only this tenant's rows. Adding a redundant .eq('school_id', ...) here
 * would suggest the frontend is what enforces isolation — it is not.
 *
 * school_id IS sent on insert, because the WITH CHECK clause requires it
 * to match the caller's school; a mismatch is rejected by the database.
 */
import { useCallback, useEffect, useState } from 'react';
import { supabase } from './supabase';
import { useAuth } from '../auth/AuthProvider';

type TenantTable = 'classes' | 'subjects' | 'students' | 'teachers' | 'enrollments';

export function useCollection<T>(table: TenantTable, orderBy = 'created_at') {
  const { schoolId } = useAuth();
  const [rows, setRows] = useState<T[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.from(table).select('*').order(orderBy);
    setRows((data ?? []) as T[]);
    setError(error?.message ?? null);
    setLoading(false);
  }, [table, orderBy]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const create = useCallback(
    async (values: Record<string, unknown>) => {
      const { error } = await supabase.from(table).insert({ ...values, school_id: schoolId });
      // 42501 surfaces when WITH CHECK rejects the row (wrong tenant or role).
      if (error) throw error;
      await refresh();
    },
    [table, schoolId, refresh],
  );

  const remove = useCallback(
    async (id: string) => {
      const { error } = await supabase.from(table).delete().eq('id', id);
      if (error) throw error;
      await refresh();
    },
    [table, refresh],
  );

  return { rows, loading, error, refresh, create, remove };
}
