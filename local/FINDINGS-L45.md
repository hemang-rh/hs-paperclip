## Migrations (L4)

Date: 2026-08-12  
Stack: `paperclip-l45` (`COMPOSE_PROJECT_NAME=paperclip-l45`, host port `3120`)  
Image: `ghcr.io/paperclipai/paperclip:sha-e55d702`  
Fresh anonymous volumes for each scenario (`docker compose down -v` between tests).

Non-TTY confirmation (Cloud Run condition): compose `paperclip` service runs with
`OpenStdin=false`, `Tty=false`; `test -t 0` inside the container prints `stdin_is_tty=no`.
All L4 scenarios used `docker compose run --no-TTY` or the detached service (no `-t`).

### 1. Fresh DB + `PAPERCLIP_MIGRATION_AUTO_APPLY=true`

Env from `local/.env` (includes `PAPERCLIP_MIGRATION_AUTO_APPLY=true`).

| Milestone | Timestamp (UTC) | Elapsed |
|-----------|-----------------|---------|
| paperclip container `StartedAt` | 2026-08-12T19:26:23.566Z | — |
| `Applying 182 pending migrations for PostgreSQL` | 19:26:27 | ~4 s after container start |
| `Server listening on 0.0.0.0:3100` | 19:26:29 | ~2 s migration phase |
| Banner `Migrations applied (pending migrations)` | 19:26:29 | — |

**Migration phase duration: ~2 seconds** (log 19:26:27 → 19:26:29).  
**Container start → listening: ~6 seconds.**

Cloud Run startup probe budget is **240 s**. Migrations fit comfortably; the Job is
**preferable for controlled deploys**, not mandatory on time grounds alone.

### 2. Fresh DB, `AUTO_APPLY` unset, `PAPERCLIP_MIGRATION_PROMPT=never`

Override via compose run (`.env` still loaded for other vars; `-e` overrides migration vars):

```bash
docker compose --env-file .env run --rm --no-TTY \
  -e PAPERCLIP_MIGRATION_AUTO_APPLY= \
  -e PAPERCLIP_MIGRATION_PROMPT=never \
  paperclip
```

**Exit code: `1`**

Exact error:

```text
PostgreSQL has pending migrations (0000_mature_masked_marvel.sql, 0001_fast_northstar.sql, 0002_big_zaladane.sql (+179 more)). Refusing to start against a stale schema. Run pnpm db:migrate or set PAPERCLIP_MIGRATION_AUTO_APPLY=true.
```

Log prefix: `Paperclip server failed to start` (`ensureMigrations` in `server/dist/index.js:99`).

Confirms `PAPERCLIP_MIGRATION_PROMPT=never` wins over the non-TTY auto-apply path when
pending migrations exist.

### 3. Migrated DB + `PAPERCLIP_MIGRATION_PROMPT=never`

DB migrated first via L5 job command (182 migrations). Then same overrides as test 2:

```bash
docker compose --env-file .env run -d --no-TTY --name paperclip-l45-test3 \
  -e PAPERCLIP_MIGRATION_AUTO_APPLY= \
  -e PAPERCLIP_MIGRATION_PROMPT=never \
  paperclip
```

**Result: started normally.** Container `Status=running`, `ExitCode=0`.  
Banner: `Migrations already applied`.  
Log: `Server listening on 0.0.0.0:3100` at 19:24:42Z. No refusal, no re-apply.

### 4. Non-TTY

All runs match Cloud Run: no stdin TTY (`OpenStdin=false`, `Tty=false`, `stdin_is_tty=no`).

---

## Migration job (L5)

Image: `ghcr.io/paperclipai/paperclip:sha-e55d702`  
Postgres: `postgres://paperclip:paperclip@db:5432/paperclip` (compose `db` service).

### OCI labels (`docker inspect`)

| Label | Value |
|-------|-------|
| `io.github.paperclipai.schema.last-migration` | `0183_connection_user_authorization_state.sql` |
| `io.github.paperclipai.schema.migration-count` | `182` |

### Working Cloud Run Job command

Entrypoint override avoids the server boot path; working directory is `/app`.

```bash
docker compose --env-file .env run --rm --no-TTY \
  --entrypoint "" \
  -e DATABASE_URL=postgres://paperclip:paperclip@db:5432/paperclip \
  paperclip \
  sh -c 'cd /app && pnpm --filter @paperclipai/db migrate'
```

**Cloud Run Job equivalent:**

- **Command:** `sh`, `-c`, `cd /app && pnpm --filter @paperclipai/db migrate`
- **Entrypoint override:** empty (or `/bin/sh` if the platform requires an explicit entrypoint)
- **Env:** `DATABASE_URL` (Cloud SQL connection string in production)
- **Working dir:** `/app` (image default)

Default image entrypoint (`docker-entrypoint.sh` → `gosu node …`) also works when the
command is overridden to the `sh -c` migrate line above (verified on no-op rerun).

### Runtime deps

`pnpm --filter @paperclipai/db migrate` runs:

1. `pnpm run check:migrations` → `tsx src/check-migration-numbering.ts` + safety check
2. `tsx src/migrate.ts`

Both steps succeed in the production image. Dev tooling (`tsx`) is available via the
monorepo install; no fallback command was needed.

### Empirical runs

| Run | DB state | Output | Duration | Exit |
|-----|----------|--------|----------|------|
| 1 | Empty | `Applying 182 pending migration(s)...` → `Migrations complete` | ~4 s | 0 |
| 2 | Migrated | `No pending migrations` | ~4 s | 0 |

Second run is a clean no-op (checks + exit 0).
