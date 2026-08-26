# Multi-tenant school management SaaS — technical foundation

One deployment serving many schools, with **total data isolation between
tenants enforced inside the database**. This repository is the
scaffolding phase: authentication, roles, the structural CRUD entities,
the schema with RLS, and an executable proof that a user of school A can
never read or write data of school B.

Part of the educational business logic (grading, academic periods) is
**intentionally not implemented** — it depends on validation with a
partner school that has not happened yet. See
[Scope](#scope--built-vs-deliberately-deferred).

---

## The problem

Small and mid-sized private schools run on spreadsheets and WhatsApp
groups: enrollment lists in one file, grades in another, no single place
where the school office, the teacher and the family see the same data.
Buying one system per school is expensive to sell and to operate; the
viable model is a single hosted product that many schools share.

That turns the hardest requirement into a data-privacy one: two schools
in the same database, and no path — not a bug, not a forged request, not
a mistaken query — where one sees the other's students.

## Architecture decision: row-level tenancy + RLS

Each school is a tenant. Every table holding school data carries
`school_id`, and **PostgreSQL Row Level Security** is what enforces the
boundary — not the application code.

| Option | Why not |
| --- | --- |
| One database per school | Migrations, backups and monitoring multiply by the number of schools. Not viable for a small team. |
| One schema per school | Same operational problem, plus connection-pool and type-generation friction. |
| **Shared schema + RLS** | **Chosen.** One migration path; isolation lives in Postgres, so a frontend bug cannot leak data. |

The consequence that matters in review: **the frontend never filters by
`school_id`**. Queries are written as `select('*')` and Postgres returns
only the caller's rows. If the isolation logic were a `where` clause in
application code, every new query would be a chance to forget it.

How it works, end to end:

1. A user signs in through Supabase Auth and gets a JWT.
2. `public.profiles` binds that user id to a `school_id` and a `role`
   (`super_admin`, `school_admin`, `teacher`, `student`). A CHECK
   constraint makes the binding mandatory: only `super_admin` may have a
   null school.
3. `SECURITY DEFINER` helpers (`app.current_school_id()`,
   `app.current_role()`) resolve the caller's tenant. They bypass RLS on
   purpose — a policy on `profiles` that queried `profiles` would
   recurse forever.
4. Every policy reduces to *"is this row in my school, and does my role
   allow this action?"*, with `USING` governing reads and `WITH CHECK`
   governing writes. Both are needed: `USING` alone leaves inserts open.
5. Join tables use **composite foreign keys** including `school_id`, so
   even a `super_admin` cannot enroll a student of school A in a class of
   school B.

Full commentary lives in
[`supabase/migrations/20260826120100_rls_policies.sql`](supabase/migrations/20260826120100_rls_policies.sql).

## Data model

```
schools ──┬── profiles (school_id, role)  ← the tenant binding
          ├── classes            ┐
          ├── subjects           ├─ structural entities, all school_id NOT NULL
          ├── students           │
          ├── teachers           ┘
          ├── enrollments          (student ↔ class)
          ├── teacher_assignments  (teacher ↔ class ↔ subject)
          └── grades               (raw values only — no computation)
```

`grades` is deliberately neutral: `student_id`, `class_id`, `subject_id`,
`value`, `date`. No period column, no weights, no averages, no pass/fail
flag. `date` is enough to reconstruct bimesters, trimesters or semesters
later, once the partner school confirms which one they use — so the
schema leaves room for the rule without committing to it.

## Isolation is tested, not asserted

Two independent proofs, both runnable:

```bash
npm run test:isolation      # client path: supabase-js → PostgREST → RLS
npm run test:isolation:sql  # database path: impersonated JWT claims in psql
```

Cases covered by both: cross-tenant read returns zero rows; cross-tenant
insert is rejected with `42501`; cross-tenant update/delete affects zero
rows; moving an owned row into another tenant is rejected; a teacher
cannot create classes; a student sees only their own record and grades; a
student cannot escalate their own role; `super_admin` crosses tenants by
design.

The tests use the **anon key only**. The service role key bypasses RLS,
so a test that used it would prove nothing.

## Running locally

Requires Node 20+, Docker, and the Supabase CLI.

```bash
git clone <repo> && cd school-saas
npm install
cp .env.example .env.local          # then paste the keys printed below

supabase start                      # local Postgres + Auth + API
supabase db reset                   # applies migrations + seed.sql
npm run db:types                    # generates src/lib/database.types.ts

npm run dev                         # http://localhost:5173
```

`supabase start` prints the API URL and the anon key — put them in
`.env.local` as `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`.

### Seeded accounts (password `senha123`)

| Email | Role | School |
| --- | --- | --- |
| `owner@plataforma.dev` | super_admin | — (platform) |
| `admin@aurora.test` | school_admin | Colégio Aurora |
| `prof@aurora.test` | teacher | Colégio Aurora |
| `aluno@aurora.test` | student | Colégio Aurora |
| `admin@bandeirante.test` | school_admin | Instituto Bandeirante |
| `prof@bandeirante.test` | teacher | Instituto Bandeirante |
| `aluno@bandeirante.test` | student | Instituto Bandeirante |

Log in as the two `school_admin` accounts side by side: the class named
"9º ano A" exists in both schools and neither sees the other's.

## Deploy (Vercel)

Import the repo, keep the detected Vite preset, and set
`VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as environment
variables. `vercel.json` adds the SPA rewrite and baseline security
headers. Point the project at a hosted Supabase instance and run
`supabase db push` to apply the migrations there.

## Scope — built vs. deliberately deferred

### Built in this phase

- Multi-tenant schema with `school_id` on every school-scoped table.
- RLS policies written with the schema, commented policy by policy.
- Supabase Auth + `profiles` binding every user to a school and a role.
- Role-based route protection (`RequireRole`), with the security
  boundary in the database, not in the guard.
- CRUD for `schools` (super_admin), `classes`, `subjects`, `students`
  + `enrollments`, `teachers` + `teacher_assignments` (school_admin).
- Screens: login, per-role dashboard, class / subject / student lists
  and forms, tenant isolation report.
- Seed with 2 schools and one user per role in each.
- Automated isolation proof at the client and database levels.
- Responsive, mobile-first layout.

### Deliberately deferred (pending validation with the partner school)

| Not built | Why |
| --- | --- |
| Average/grade calculation | Formula and per-assessment weights unconfirmed. |
| Retake rules (*recuperação*) | Parallel vs. final retake changes the model. |
| Academic period structure | Bimester vs. trimester vs. semester — hardcoding one would force a migration later. |
| Report card PDF | Depends on all of the above. |
| Notifications (email/push/WhatsApp) | Channel and triggers undefined. |
| Native mobile app | Responsive web only for now. |

`grades` exists as a neutral table so grade data can be captured before
those rules are settled. Nothing computes on top of it yet.

Next step: validation meeting with the partner school, then design the
period + grading model on top of the existing `grades` table.
