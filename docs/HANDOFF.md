# Handoff — implementation spec

For the agent/developer turning this foundation into the running app.
The database layer, the auth plumbing and the tests in this repo are
**already written**; what is missing is the screen implementation, which
should follow the prototype in `Prototipo Gestao Escolar.dc.html`.

Read first: `README.md` (architecture decision), then
`supabase/migrations/20260826120100_rls_policies.sql` (the isolation
rules the UI must not try to duplicate).

## Ground rules

1. **Never filter by `school_id` in a read.** RLS already scopes reads.
   Adding the filter suggests the frontend is what enforces isolation.
   The only place `school_id` is sent from the client is on **insert**,
   where `WITH CHECK` validates it.
2. **Never import the service role key** into `src/`. Only
   `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`.
3. **Route guards are UX, not security** (`src/auth/RequireRole.tsx`).
   A forged route must still return zero rows.
4. **Do not implement anything in the deferred list** in the README —
   no averages, no academic period column, no report card, no
   notifications. If a screen seems to need one, stop and flag it.
5. Comments and identifiers in English; all UI copy in pt-BR.

## Already in the repo

| Path | Contents |
| --- | --- |
| `supabase/migrations/20260826120000_init_schema.sql` | Tables, tenant columns, composite FKs, neutral `grades`. |
| `supabase/migrations/20260826120100_rls_policies.sql` | Helper functions, signup trigger, all policies. |
| `supabase/seed.sql` | 2 schools, 7 users, structural data. |
| `supabase/tests/tenant_isolation.sql` | DB-level isolation proof (psql). |
| `tests/tenant-isolation.test.ts` | Client-level isolation proof (vitest). |
| `src/lib/supabase.ts` | Browser client. |
| `src/lib/types.ts` | Domain type aliases over generated `Database`. |
| `src/lib/useCollection.ts` | The one data-access pattern for list screens. |
| `src/auth/AuthProvider.tsx` | Session + profile (tenant binding). |
| `src/auth/RequireRole.tsx` | Guard + `roleHome()`. |
| `vercel.json`, `.env.example`, `package.json` | Deploy, env, scripts. |

Generate `src/lib/database.types.ts` before the first build:
`npm run db:types`. Vite/TS/Tailwind config files come from
`npm create vite@latest -- --template react-ts` plus the Tailwind init;
they are intentionally not checked in as hand-written boilerplate.

## To build

### Routes

| Path | Guard | Screen |
| --- | --- | --- |
| `/login` | public | Login |
| `/platform/schools` | `super_admin` | School list + create form |
| `/platform/isolation` | `super_admin` | Isolation report |
| `/school` | `school_admin` | Placeholder dashboard |
| `/school/classes` | `school_admin` | Class list + form |
| `/school/subjects` | `school_admin` | Subject list + form |
| `/school/students` | `school_admin` | Student list + enrollment form |
| `/school/isolation` | `school_admin` | Isolation report |
| `/teacher` | `teacher` | Placeholder dashboard |
| `/student` | `student` | Placeholder dashboard |

`/` redirects through `roleHome(role)`. Unknown role or missing profile
lands on `/login`.

### Shell

Collapsible sidebar (248px expanded, 58px collapsed, state persisted in
`localStorage`). Below 768px it becomes an off-canvas drawer over a
sticky top bar — build mobile first and treat the sidebar as the
enhancement. Header shows the tenant scope line (`school_id`, `role`),
the screen title and a one-line subtitle.

### List + form screens

One shared pattern for classes, subjects and students, backed by
`useCollection`:

- table with the columns shown in the prototype, delete action per row;
- empty state naming the table (`select * from classes`);
- side form; `school_id` comes from the session, never from an input;
- surface `error.code === '42501'` as a plain-language message — it means
  the role or the tenant check rejected the write.

Student creation inserts into `students` **and** `enrollments` in the
same submit (class picked from the tenant's classes). Wrap it so a failed
enrollment does not leave an orphan student — a `supabase.rpc` function
is acceptable here, or insert student then enrollment with cleanup on
failure. Do not add a period or grade column to either table.

### Isolation report screen

The portfolio centrepiece. It must read as evidence, not decoration:

- one row per case (query, actor, expected outcome, PASS badge);
- a "run" action that executes the cases live through the anon client
  with the current session and shows the real result;
- three manual buttons — read other tenant, insert into other tenant,
  self-escalate role — appending the raw Postgres response to a console
  block, including the `42501` code;
- link the exact commands (`npm run test:isolation`,
  `npm run test:isolation:sql`) so a reviewer can reproduce it.

Cases must match `tests/tenant-isolation.test.ts`; if one is added there,
add it here too.

### Dashboards

Deliberately empty: three stat tiles from counts the caller can already
read, plus a dashed "área reservada" card explaining that the content
depends on the pending validation. No charts, no grade widgets.

## Definition of done

- `npm run build` clean, `npm run test` green.
- `npm run test:isolation:sql` green against a fresh `supabase db reset`.
- Logging in as `admin@aurora.test` and `admin@bandeirante.test` side by
  side shows the same class name in both and no shared rows.
- No `school_id` filter in any read in `src/`.
- No file in `src/` references the service role key.
- Deferred list in the README still accurate — nothing from it shipped.
