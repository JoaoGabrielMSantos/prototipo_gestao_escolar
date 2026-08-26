/**
 * RequireRole — route guard.
 *
 * IMPORTANT: this is UX, not security. Hiding a route hides a screen,
 * not the data. The actual authorization lives in the RLS policies, so
 * a user who forges a route still gets zero rows from Postgres. Keeping
 * that separation explicit is the point: the guard may be wrong without
 * ever becoming a data leak.
 */
import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from './AuthProvider';
import type { UserRole } from '../lib/types';

export function RequireRole({ allow, children }: { allow: UserRole[]; children: ReactNode }) {
  const { session, role, loading } = useAuth();
  const location = useLocation();

  // Do not decide anything until the profile (and therefore the role) is known.
  if (loading) return <div className="p-8 text-sm text-neutral-500">Carregando…</div>;

  if (!session) return <Navigate to="/login" replace state={{ from: location.pathname }} />;

  if (!role || !allow.includes(role)) return <Navigate to="/" replace />;

  return <>{children}</>;
}

/** Landing route per role — a single place that owns "where do I go after login". */
export function roleHome(role: UserRole | null): string {
  switch (role) {
    case 'super_admin':
      return '/platform/schools';
    case 'school_admin':
      return '/school';
    case 'teacher':
      return '/teacher';
    case 'student':
      return '/student';
    default:
      return '/login';
  }
}
