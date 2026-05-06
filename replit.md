# 3D Product Studio

A web pipeline manager for generating 3D models and AR videos of pet products (cat trees, beds, niches, etc.) using a local RTX 5090 GPU workstation running Hunyuan3D-2 + Blender.

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
- API: Express 5 + multer (file uploads)
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)
- Worker: Python 3.10+, Hunyuan3D-2, Blender 4.x, rembg

## Where things live

- `lib/api-spec/openapi.yaml` — OpenAPI spec (source of truth for all contracts)
- `lib/db/src/schema/` — Drizzle table definitions (products.ts, workers.ts, jobs.ts)
- `artifacts/api-server/src/routes/` — Express route handlers (products, jobs, workers, stats, uploads)
- `artifacts/api-server/uploads/` — rendered files served by the API
- `artifacts/studio/src/` — React frontend pages and components
- `lib/api-client-react/src/generated/api.ts` — generated React Query hooks
- `lib/api-zod/src/generated/api.ts` — generated Zod validators
- `worker/` — Python GPU worker for local RTX 5090

## Architecture decisions

- **Worker poll model**: Local GPU workstations poll `GET /api/jobs/next` to claim pending jobs, then push status updates via `PATCH /api/jobs/:id/status`. No WebSocket required.
- **Pipeline stages**: pending → claimed → generating_3d (Hunyuan3D-2) → compositing (Blender scene) → rendering_video → completed/failed
- **File uploads**: Worker posts rendered videos/thumbnails/GLBs to `POST /api/uploads`; served back via `GET /api/uploads/:fileName`.
- **Codegen script patches api-zod index**: Orval regenerates `lib/api-zod/src/index.ts` with stale exports; the codegen script overwrites it to only export from `./generated/api`.
- **Array fields**: Product `imageUrls` stored as Postgres text array; insert uses `ARRAY[]::text[]` syntax.

## Product

- Upload pet products (images, dimensions, material, description)
- Queue render jobs with scene type (living room, bedroom, balcony, garden, kitchen) and animal type (cat, dog, none)
- Local RTX 5090 worker polls for jobs, runs Hunyuan3D-2 → Blender scene + Cycles render → video
- Dashboard shows live pipeline health, job status breakdown, recent activity
- Worker node management with heartbeat monitoring

## User preferences

- Local GPU workstation (RTX 5090, 64GB RAM) — highest quality, all free/open-source tools
- 3D generation: **Hunyuan3D-2** (Tencent, MIT license) — best quality free local model
- Output: AR-quality video of product in realistic home environment with cat/dog
- No pricing concerns — maximize potential

## Gotchas

- Run `pnpm --filter @workspace/api-spec run codegen` after any OpenAPI spec change
- `pnpm --filter @workspace/db run push` for schema changes; use `push-force` if column conflicts
- Worker nodes must call `POST /api/workers` to register, then poll `GET /api/jobs/next` and post heartbeats
- Worker setup: run `bash worker/setup.sh` once on the RTX 5090 machine (downloads ~7GB Hunyuan3D-2 weights)

## Pointers

- `worker/README.md` — full worker setup and run instructions
- `worker/worker.py` — main Python worker script (runs on RTX 5090)
- `worker/setup.sh` — one-time setup script (clones Hunyuan3D-2, installs deps)
- `worker/blender_scenes/` — Blender Python scene scripts (one per scene type)
