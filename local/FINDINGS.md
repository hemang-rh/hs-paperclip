# Local Docker Compose Harness — Validation Findings

Date: 2026-08-10  
Image: `ghcr.io/paperclipai/paperclip:sha-e55d702`  
Project: `paperclip-local` (from `COMPOSE_PROJECT_NAME`)  
Host port: `3100` (from `PAPERCLIP_HOST_PORT`)

## Harness

- `docker-compose.yml` — paperclip + postgres:17-alpine + MinIO + `mc` bucket init
- `.env.example` / `.env` — fixed, reproducible secrets; compose reads `local/.env`
- **No volume mounted on `/paperclip`** (confirmed `Mounts: []`); directory is ephemeral and was created at runtime by the entrypoint
- Isolation knobs: `COMPOSE_PROJECT_NAME`, `PAPERCLIP_HOST_PORT`

## 1. Listening / time to healthy

**Yes — server reached a listening state.**

| Milestone | UTC timestamp | Notes |
|-----------|---------------|-------|
| `docker compose up -d` | 00:13:18Z | network + containers created |
| `db` healthy + `minio-init` exited 0 | ~00:13:23Z | paperclip then started |
| paperclip container StartedAt | 00:13:23.753Z | |
| `Server listening on 0.0.0.0:3100` | 00:13:29Z | after applying 182 pending migrations |
| `GET /api/health` → 200 | shortly after listen | |

**Time from `up` to listening: ~11 seconds** (00:13:18 → 00:13:29), dominated by first-boot Postgres migrations.

On a subsequent `docker compose restart paperclip` (DB already migrated), listen again happened within a few seconds; health remained 200.

Banner confirmed:

- Deploy: `authenticated (public)`
- Bind: `lan (0.0.0.0)`
- Mode: `external-postgres | static-ui`

## 2. `GET /api/health`

**HTTP 200.** Body:

```json
{
  "status": "ok",
  "deploymentMode": "authenticated",
  "deploymentExposure": "public",
  "bootstrapStatus": "bootstrap_pending",
  "bootstrapInviteActive": false
}
```

`bootstrap_pending` is expected for a fresh DB with no bootstrap invite redeemed yet.

## 3. Plugin coordinator / plugin-loader logs

| Expected string | Observed? |
|-----------------|-----------|
| `plugin job coordinator started` | **Yes** — `plugin job coordinator started — listening to lifecycle events` |
| `plugin-loader: loadAll complete` | **No exact match** |

Actual plugin-loader lines on this image/build:

```
plugin-loader: loading all ready plugins
plugin-loader: no ready plugins to load
```

So the loader finished the empty path successfully, but this tag does not emit the literal `plugin-loader: loadAll complete` string.

## 4. CRITICAL: `PAPERCLIP_DEPLOYMENT_EXPOSURE=public` + plain HTTP `PAPERCLIP_PUBLIC_URL`

**Did not reject.** Server started cleanly with:

- `PAPERCLIP_DEPLOYMENT_EXPOSURE=public`
- `PAPERCLIP_PUBLIC_URL=http://localhost:3100`
- `PAPERCLIP_API_URL=http://localhost:3100`

Evidence:

- Banner: `Deploy authenticated (public)`
- Auth log accepted the HTTP origin explicitly:

  `authPublicBaseUrl":"http://localhost:3100/"` with trusted origins including `http://localhost:3100` and `http://localhost`
- No startup error/fatal related to HTTPS, public URL, or exposure mode
- Health reports `"deploymentExposure":"public"`

**Implication for Cloud Run:** this particular release (`sha-e55d702` / v2026.722.0) allows `http://` public URLs at least for localhost. That does **not** prove a non-localhost `http://` public URL would be accepted on Cloud Run — only that the feared localhost HTTP rejection did **not** occur here. We did **not** switch exposure to `private`.

## 5. Peak memory (paperclip container)

Measured on the cold first boot (182 migrations + full startup), before any restart reset the cgroup counters:

| Metric | Value |
|--------|-------|
| cgroup v2 `memory.peak` (first boot) | **788.8 MiB** (827,097,088 bytes) |
| Steady-state `docker stats` after listen | ~378–380 MiB |
| Restart peak (`docker stats` sampling) | ~712.6 MiB |
| Restart cgroup `memory.peak` | ~716.1 MiB |

**Recommend sizing Cloud Run memory with headroom above ~800 MiB** for cold start (tmpfs writable layer counts against the same limit). Steady-state idle is closer to ~380 MiB in this harness, but peak matters for OOM risk.

## Stateless / deps sanity

- `/paperclip` exists, owned by `node`, holds `instances/default/...` written at runtime — all ephemeral (lost on container replace), as intended for Cloud Run.
- Postgres healthcheck (`pg_isready`) gated app start.
- MinIO + `mc` init created bucket `paperclip-uploads` (`minio-init` exited 0).
- S3 env pointed at `http://minio:9000` with path-style + `minioadmin` credentials; server started with that config (no storage smoke upload performed in this pass).

## How to re-run

```bash
cd local
cp -n .env.example .env   # if needed
docker compose --env-file .env up -d
curl -sS http://localhost:${PAPERCLIP_HOST_PORT:-3100}/api/health
docker compose --env-file .env logs -f paperclip
```

Side-by-side stacks:

```bash
COMPOSE_PROJECT_NAME=paperclip-a PAPERCLIP_HOST_PORT=3110 docker compose --env-file .env up -d
COMPOSE_PROJECT_NAME=paperclip-b PAPERCLIP_HOST_PORT=3120 docker compose --env-file .env up -d
```

## Bootstrap / first admin (follow-up)

The landing page saying the instance is waiting on its first admin is **expected**
in `authenticated/public` mode: browser self-claim is disabled.

Do **not** run `pnpm paperclipai auth bootstrap-ceo` on the Mac host in this repo
(`ERR_PNPM_NO_IMPORTER_MANIFEST_FOUND` — no Paperclip `package.json` here).

Run the CLI inside the container instead:

```bash
cd local
./bootstrap-admin.sh
```

That seeds a minimal `config.json` (CLI requires it; the server does not write one
on env-only boot) and prints a one-time invite URL to open in the browser.

Example invite minted during this session:

`http://localhost:3100/invite/pcp_bootstrap_1ce8eaf4ef0f89a78ee559127e787f745fd53d96dbb0c33e`
