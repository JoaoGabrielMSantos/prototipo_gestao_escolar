repo: JoaoGabrielMSantos/prototipo_gestao_escolar
branch: main

## Last sync
date: 2026-08-26T15:58:59Z
status: repository created but empty (LICENSE only) — project files not pushed yet

### Updated in this project
- Multi-tenant schema + RLS policies written locally (supabase/migrations)
- Seed with 2 test schools and one user per role
- Isolation proofs: SQL (psql) and client-level (vitest, anon key only)
- Navigable prototype: Prototipo Gestao Escolar.dc.html

## Screen map
| Screen | Built from |
| --- | --- |
| Login | prototype only (docs/HANDOFF.md routes table) |
| Escolas (super_admin) | supabase/migrations/20260826120100_rls_policies.sql (schools_write) |
| Turmas / Disciplinas / Alunos | supabase/migrations/20260826120000_init_schema.sql, src/lib/useCollection.ts |
| Isolamento entre tenants | supabase/tests/tenant_isolation.sql, tests/tenant-isolation.test.ts |
| Dashboards por papel | src/auth/RequireRole.tsx (roleHome) |
