/**
 * Supabase browser client. Single instance for the whole app.
 *
 * Only the anon key ever reaches the browser. Every query it makes is
 * evaluated against RLS with the logged-in user's JWT, which is why the
 * frontend never needs to add "where school_id = ..." by hand — and why
 * a bug in the frontend cannot leak another school's data.
 *
 * The service role key must NEVER appear in this file or in any VITE_*
 * variable: anything prefixed VITE_ is bundled into the client.
 */
import { createClient } from '@supabase/supabase-js';
import type { Database } from './database.types';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error('Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY. See .env.example');
}

export const supabase = createClient<Database>(url, anonKey, {
  auth: { persistSession: true, autoRefreshToken: true },
});
