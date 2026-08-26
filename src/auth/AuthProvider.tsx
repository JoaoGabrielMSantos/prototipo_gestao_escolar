/**
 * AuthProvider — resolves the session AND the tenant binding.
 *
 * Two distinct pieces of state matter here:
 *   session — from Supabase Auth (who is logged in)
 *   profile — from public.profiles (which school + which role)
 *
 * Route guards depend on `profile`, so the app must not render guarded
 * routes until it has loaded. `loading` covers that window; skipping it
 * causes a flash of the wrong screen or a spurious redirect to /login.
 *
 * Note that the profile query has no school filter: RLS guarantees the
 * only readable row is the caller's own.
 */
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import type { Profile, UserRole } from '../lib/types';

type AuthState = {
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
  role: UserRole | null;
  schoolId: string | null;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthState | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;

    async function loadProfile(next: Session | null) {
      if (!next) {
        setProfile(null);
        setLoading(false);
        return;
      }
      const { data, error } = await supabase
        .from('profiles')
        .select('id, school_id, role, full_name')
        .eq('id', next.user.id)
        .single();

      if (!active) return;
      if (error) {
        // A session without a profile means the provisioning trigger did
        // not run: fail closed rather than rendering an unscoped app.
        console.error('profile lookup failed', error);
        await supabase.auth.signOut();
        setProfile(null);
      } else {
        setProfile(data);
      }
      setLoading(false);
    }

    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      loadProfile(data.session);
    });

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      setLoading(true);
      loadProfile(next);
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  const value: AuthState = {
    session,
    profile,
    loading,
    role: profile?.role ?? null,
    schoolId: profile?.school_id ?? null,
    async signIn(email, password) {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
    },
    async signOut() {
      await supabase.auth.signOut();
    },
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
