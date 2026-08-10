# Local Paperclip harness

Docker Compose stack for validating a **stateless** Paperclip deploy before Cloud Run.
Uses the published image `ghcr.io/paperclipai/paperclip:sha-e55d702` (v2026.722.0) —
no source build.

Services: Paperclip (port 3100), Postgres 17, MinIO + bucket init. `/paperclip` is
**not** volume-mounted (ephemeral, Cloud Run–like).

Validation notes live in [`FINDINGS.md`](./FINDINGS.md).

---

## Prerequisites

- Docker Desktop running (~10 GB free disk for the first pull; image ~1.46 GB compressed)
- Apple Silicon and Intel both work (multi-arch image)

---

## Run it

```bash
cd local
cp -n .env.example .env          # first time only; fixed secrets for reproducible restarts
docker compose --env-file .env up -d
```

First `up` pulls images (can take a while) and applies DB migrations. Expect the app to
listen within ~10–15 seconds after containers start.

Check health:

```bash
curl -sS http://localhost:3100/api/health
# open http://localhost:3100 in a browser
```

Healthy response looks like:

```json
{
  "status": "ok",
  "deploymentMode": "authenticated",
  "deploymentExposure": "public",
  "bootstrapStatus": "bootstrap_pending",
  "bootstrapInviteActive": false
}
```

---

## First admin (required once)

The UI will say the instance is waiting on its first admin. In
`authenticated` / `public` mode, browser self-claim is **disabled** — you must mint a
one-time invite from the host that runs Paperclip.

**Do not** run `pnpm paperclipai auth bootstrap-ceo` on your Mac in this repo. There is
no Paperclip `package.json` here, so pnpm fails with `ERR_PNPM_NO_IMPORTER_MANIFEST_FOUND`.

Run the CLI **inside** the container:

```bash
cd local
./bootstrap-admin.sh
```

That script:

1. Seeds a minimal `config.json` in the container (the server boots from env alone and
   never writes this file; the CLI still requires it).
2. Runs `pnpm paperclipai auth bootstrap-ceo` and prints an invite URL.

Open the URL in your browser, create the account, and finish setup.

Equivalent one-liner (if you prefer not to use the script):

```bash
docker compose --env-file .env exec paperclip \
  sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo --base-url http://localhost:3100'
```

(You’ll get “No config found” unless `config.json` already exists — prefer
`./bootstrap-admin.sh`.)

---

## Useful commands

```bash
# logs
docker compose --env-file .env logs -f paperclip

# stop containers (keep data in postgres/minio volumes — none of our services use
# named volumes today; recreate is a full wipe)
docker compose --env-file .env down

# tear down and remove anonymous volumes
docker compose --env-file .env down -v

# replace only the app container (statelessness check)
docker compose --env-file .env rm -sf paperclip
docker compose --env-file .env up -d paperclip
```

---

## Side-by-side stacks

`COMPOSE_PROJECT_NAME` and `PAPERCLIP_HOST_PORT` are parameterized so several harnesses
can run at once (needed for later Phase L tests):

```bash
COMPOSE_PROJECT_NAME=paperclip-a PAPERCLIP_HOST_PORT=3110 \
  docker compose --env-file .env up -d

COMPOSE_PROJECT_NAME=paperclip-b PAPERCLIP_HOST_PORT=3120 \
  docker compose --env-file .env up -d
```

When using a non-default host port, set `PAPERCLIP_PUBLIC_URL` / `PAPERCLIP_API_URL` in that
stack’s env to match (or pass them on the command line) before minting a bootstrap invite.

---

## Files

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | paperclip + postgres + minio + mc init |
| `.env.example` | documented, fixed local secrets |
| `.env` | compose input (copy of example; not for production) |
| `bootstrap-admin.sh` | mint first-admin invite inside the container |
| `FINDINGS.md` | empirical validation results |
