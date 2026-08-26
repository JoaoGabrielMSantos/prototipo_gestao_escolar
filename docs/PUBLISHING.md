# Publicando este repositório

Passo a passo para subir esta pasta para o GitHub e ligar no Vercel.

## 1. Criar o repositório

No GitHub: **New repository** → nome sugerido `school-saas-multitenant`
(ou `gestao-escolar-multitenant`), visibilidade pública se for peça de
portfólio, **sem** README/`.gitignore`/licença (já existem aqui).

## 2. Primeiro push

```bash
cd <esta-pasta>
git init
git add .
git commit -m "feat: multi-tenant foundation — schema, RLS, auth, isolation tests"
git branch -M main
git remote add origin git@github.com:<seu-usuario>/school-saas-multitenant.git
git push -u origin main
```

`.gitignore` já bloqueia `.env.local`, `node_modules/`, `dist/` e o
`src/lib/database.types.ts` (é gerado por `npm run db:types`).

## 3. O que vai no repo

| Vai | Não vai |
| --- | --- |
| `supabase/` — migrations, seed, teste SQL | `.env.local` (chaves reais) |
| `tests/` — teste de isolamento em vitest | `src/lib/database.types.ts` (gerado) |
| `src/` — client, auth, hook de dados | `node_modules/`, `dist/` |
| `README.md`, `docs/HANDOFF.md` | |
| `package.json`, `vercel.json`, `.env.example` | |

`Prototipo Gestao Escolar.dc.html` e `support.js` são o protótipo de
design, não código da aplicação. Duas opções: mover para
`docs/prototype/` antes do commit (útil em entrevista — mostra o design
antes da implementação), ou adicionar as duas linhas ao `.gitignore` se
preferir o repo só com código.

## 4. Antes de rodar `npm install`

Os arquivos de config do Vite/Tailwind/TS não estão versionados de
propósito — são boilerplate de scaffold. Gere-os uma vez:

```bash
npm create vite@latest . -- --template react-ts   # aceite sobrescrever só os configs
npx tailwindcss init -p
```

Mantenha o `package.json` deste repo (ele tem os scripts `db:reset`,
`db:types`, `test:isolation`, `test:isolation:sql`); se o scaffold
sobrescrever, restaure com `git checkout package.json`.

Depois siga a seção **Running locally** do README.

## 5. Deploy no Vercel

Import do repo → preset Vite (detectado) → variáveis de ambiente
`VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` apontando para a instância
Supabase hospedada. `vercel.json` já traz o rewrite de SPA e os headers
de segurança. Aplique o schema no projeto hospedado com
`supabase db push`.

## 6. Sugestão de descrição do repo

> SaaS multi-tenant de gestão escolar: uma instância, muitas escolas,
> isolamento garantido por Row Level Security no Postgres — com prova
> automatizada. React + TypeScript + Supabase.

Topics: `multi-tenant`, `supabase`, `row-level-security`, `postgres`,
`react`, `typescript`, `saas`.
