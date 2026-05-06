# 3D Product Studio

A web pipeline manager for generating 3D models and AR videos of pet products (cat trees, beds, niches, etc.) using a local GPU workstation running TripoSR.

## Run & Operate

- `pnpm --filter @workspace/api-server run dev` — run the API server (port 8080)
- `pnpm --filter @workspace/studio run dev` — run the React frontend (port 18425)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required env: `DATABASE_URL` — Postgres connection string

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- Frontend: React + Vite, Tailwind CSS, wouter, TanStack Query
- API: Express 5
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

- `lib/api-spec/openapi.yaml` — OpenAPI spec (source of truth for all contracts)
- `lib/db/src/schema/` — Drizzle table definitions (products.ts, workers.ts, jobs.ts)
- `artifacts/api-server/src/routes/` — Express route handlers (products, jobs, workers, stats)
- `artifacts/studio/src/` — React frontend pages and components
- `lib/api-client-react/src/generated/api.ts` — generated React Query hooks
- `lib/api-zod/src/generated/api.ts` — generated Zod validators

## Architecture decisions

- **Worker poll model**: Local GPU workstations poll `GET /api/jobs/next` to claim pending jobs, then push status updates via `PATCH /api/jobs/:id/status`. No WebSocket required.
- **Pipeline stages**: pending → claimed → generating_3d (TripoSR) → compositing (scene + animal) → rendering_video → completed/failed
- **Codegen script patches api-zod index**: Orval regenerates `lib/api-zod/src/index.ts` with stale exports; the codegen script overwrites it to only export from `./generated/api`.
- **Array fields**: Product `imageUrls` stored as Postgres text array; insert uses `ARRAY[]::text[]` syntax.
- **Stats endpoints**: Dashboard summary, per-status counts, and recent activity are dedicated endpoints so the frontend can show live pipeline health without heavy client-side aggregation.

## Product

- Upload pet products (images, dimensions, material, description)
- Queue render jobs with scene type (living room, bedroom, balcony, garden, kitchen) and animal type (cat, dog, none)
- Local GPU workstation (RTX 5090) polls for jobs and runs TripoSR → scene composition → video rendering
- Dashboard shows live pipeline health, job status breakdown, recent activity
- Worker node management with heartbeat monitoring

## User preferences

- Local GPU workstation (RTX 5090, 64GB RAM) runs TripoSR for 3D generation
- Output: AR-quality video of product in realistic home environment with cat/dog
- No pricing concerns — maximize potential

## Gotchas

- Run `pnpm --filter @workspace/api-spec run codegen` after any OpenAPI spec change; the script auto-patches the api-zod index
- `pnpm --filter @workspace/db run push` for schema changes; use `push-force` if column conflicts arise
- Worker nodes must call `POST /api/workers` to register, then poll `GET /api/jobs/next` and post heartbeats

## Pointers

- See `pnpm-workspace` skill for workspace structure
- Worker client script to run on the RTX 5090 machine: poll `/api/jobs/next`, run TripoSR, post results back via `/api/jobs/:id/status`
