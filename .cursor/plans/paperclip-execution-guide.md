# Paperclip Deployment — Execution Guide

Companion to [paperclip-deployment.md](paperclip-deployment.md). That document is the
*what and why*. This one is the *how*: per-task instructions for manual work,
copy-paste prompts for Cursor work, and where subagents can run in parallel.

Date: 2026-08-03

---

## Model selection guide

Which Cursor model to use per phase, and when to escalate. Available models in this
workspace:

| Model | Best for |
|---|---|
| **inherit** | Orchestration chat with you; reviewing findings; deciding go/no-go between phases |
| **composer-2.5-fast** | Well-specified implementation, scaffolding, parallel subagents, scripts with clear inputs |
| **gpt-5.6-terra-medium** | GCP / Terraform / Cloud Run / IAM — infrastructure correctness over raw speed |
| **gpt-5.6-sol-medium** | Cross-cutting integration, ambiguous specs, wiring modules together |
| **cursor-grok-4.5-high-fast** | Empirical debugging, behavioral probes, doc-vs-code contradictions, concurrency edge cases |

**Default rule:** use **inherit** for the conversation that drives the phase (paste prompts,
review output, decide next step). Assign **composer-2.5-fast** to parallel subagents doing
independent, bounded work. Use **terra** or **sol** for the single integrator pass that
wires everything together. Escalate to **grok** when something fails empirically and the
cause is not obvious from the spec alone.

**Do not** run five parallel subagents on terra/sol — cost and latency multiply with little
gain when each agent owns one module with an explicit prompt. Save the stronger models for
integration, proofs, and debugging.

### Per-phase recommendations

| Phase | Primary model | Subagent model | Escalate to | Why |
|---|---|---|---|---|
| **L** Local validation | inherit | see per-task below | grok | Mix of harness build, empirical probes, and doc contradictions |
| **0** GCP foundation | inherit (you run scripts) | **composer-2.5-fast** for T7 | terra | T7 is a bounded bash script; the rest is manual |
| **1** Terraform foundation | inherit | **composer-2.5-fast** ×5 modules | **gpt-5.6-terra-medium** for T9b; **grok** for T4/T5 if proofs fail | Modules are parallel and spec-driven; integration and live GCP proofs need stronger infra reasoning |
| **2** Image supply chain | inherit | **composer-2.5-fast** ×2 | terra | crane copy + one workflow; straightforward |
| **3** Service + jobs | inherit | **composer-2.5-fast** for T11b; **gpt-5.6-terra-medium** for T11a | **gpt-5.6-sol-medium** for T14; grok if bootstrap job fails | Service module is the most env-var-dense Terraform; T14 depends on L3 findings |
| **4** First admin | **inherit only** | — | grok if job logs are cryptic | Fully manual and interactive; no agent needed unless debugging |
| **5** Edge + hardening | inherit | **composer-2.5-fast** ×3 (T16, T19, T23+T24); **gpt-5.6-terra-medium** ×2 (T15, T25) | grok if WebSocket/LB behaviour surprises | ALB + Cloud Armor + monitoring need infra depth; docs and smoke script are fast |
| **6** Agent execution | inherit | **gpt-5.6-sol-medium** or **grok** for T27 | terra if fork build pipeline | Highest ambiguity; depends on T26 decision and upstream cloud-variant gap |

### Per-task overrides within Phase L

Phase L is where model choice matters most — wrong model here wastes the cheapest phase.

| Task | Model | Reason |
|---|---|---|
| **L1** Compose harness | **composer-2.5-fast** | Spec is fully written in the prompt; output is files + a smoke report |
| **L2** Statelessness restart | **composer-2.5-fast** | Runs against L1 stack; procedural |
| **L3** Bootstrap probe | **cursor-grok-4.5-high-fast** | Highest-value task; doc contradiction, upstream CLI source, iterative config.json — needs reasoning + Docker exec |
| **L4 + L5** Migrations | **composer-2.5-fast** (one subagent) | Empirical but bounded; escalate to grok only if `pnpm migrate` path fails unexpectedly |
| **L6** WebSockets + scheduler | **cursor-grok-4.5-high-fast** | Behavioral/concurrency analysis; two-container experiment |
| **L7** Sizing | **inherit** (you) | `docker stats` — 5 minutes, no agent |
| **L8** Review findings | **inherit** (you) | Go/no-go; optionally ask inherit to summarize `local/FINDINGS.md` |

### Escalation triggers (any phase)

Switch model mid-task when:

1. **First attempt fails with an unclear error** → **grok** (read logs, form hypothesis, retry).
2. **Terraform plan shows unexpected destroys or IAM expansion** → **terra** (review before apply).
3. **Parallel subagents produced modules that don't compose** → **sol** for T9b-style integration only; don't re-run all five modules.
4. **Empirical proof contradicts the plan** (e.g. `sslmode=require` ignored, public mode rejects HTTP) → **grok** to update `FINDINGS.md` and flag plan changes before GCP apply.

### Cost / speed heuristic

```
Parallel bounded work     → composer-2.5-fast
Single Terraform integrator → gpt-5.6-terra-medium
Ambiguous cross-module wiring → gpt-5.6-sol-medium
"Run it and tell me what actually happens" → cursor-grok-4.5-high-fast
You clicking in GCP console / browser → inherit (no agent)
```

---

## 0. Do you need to fork Paperclip?

**No — not for the deployment itself.** Three separate questions get conflated here, so
take them one at a time.

**Do you vendor Paperclip source into `hs-paperclip`? No.** The published image is
public — I fetched its manifest anonymously, no credentials. Your repo holds Terraform,
workflows, and scripts; it consumes `ghcr.io/paperclipai/paperclip@sha256:…` as an
external artifact, exactly the way you'd consume `postgres:17`. Vendoring a 10,000-PR
monorepo you don't modify buys you nothing and makes upgrades a merge problem.

**Do you clone it locally? Yes, as a read-only reference.** Keep a clone *outside* this
repo (e.g. `~/src/paperclip`) at the pinned tag. You'll want it for reading source when
something misbehaves, and one local test (L5) needs its migration entrypoint. Add
nothing to `hs-paperclip` except a note in the README saying which tag you're pinned to.

**Do you ever need a fork? One case, and it's real.** The `cloud` image variant —
the one with bundled sandbox-provider plugins that Phase 6 needs for remote agent
execution — **is not published for any release commit**. I checked every release tag back
to v2026.609.0:

```
v2026.722.0   sha-e55d702        exists      sha-e55d702-cloud        MISSING
v2026.720.0   sha-903bd15        exists      sha-903bd15-cloud        MISSING
v2026.707.0   sha-390627b        exists      sha-390627b-cloud        MISSING
v2026.626.0   sha-4c6c0c6        exists      sha-4c6c0c6-cloud        MISSING
v2026.618.0   sha-83a293b        exists      sha-83a293b-cloud        MISSING
v2026.609.0   sha-a0f7d3d        exists      sha-a0f7d3d-cloud        MISSING
```

705 plain `sha-` tags exist, 111 `-cloud` tags exist, 109 commits have both — and not one
of them is a release commit. So when you reach Phase 6 you pick one of three:

- Track a recent **master** commit that has both variants, giving up "latest stable".
- Use `latest-cloud`, which is a mutable tag — unacceptable for production pinning.
- **Fork and build `--target cloud` yourself** at your pinned release tag.

The third is the only one that gives you a stable, digest-pinned cloud variant. Defer the
decision to Phase 6; Phases L through 5 need no fork at all. If you do fork, it stays a
separate repo that your `image-promote` workflow builds from — still not vendored here.

---

## 1. Revised phase map

A local validation phase slots in ahead of everything. It is not busywork: four of the
riskiest unknowns in the plan (R1 bootstrap, R4 connection string, R5 WebSockets, R12
memory footprint) are answerable on your laptop for free, and each one that resolves
badly would otherwise surface as a failed Cloud Run revision.

```
Phase L  Local validation                 no GCP spend, answers R1/R4/R5/R6/R12
Phase 0  GCP foundation                   manual, one time
Phase 1  Terraform: network/data/registry/secrets/storage
Phase 2  Image supply chain
Phase 3  Terraform: migrate job -> service
Phase 4  First admin bootstrap
Phase 5  Edge, hardening, observability
Phase 6  Agent execution backend          decide fork question here
```

### Parallelization summary

| Phase | Parallel? | How to split |
|---|---|---|
| L | Partly | L1 alone first. Then 3 subagents: {L3}, {L4+L5}, {L6}. Each needs its own `COMPOSE_PROJECT_NAME` and port offset or they fight over 3100/5432. L2 and L7 piggyback on L1's stack — don't parallelize those. |
| 0 | Barely | Mostly you, mostly sequential (project → APIs → WIF → DNS). T7 (script authoring) runs in parallel with T3. |
| 1 | Yes, 5-way | After T6, one subagent per Terraform module: network, database, registry, secrets, storage. **Then a single integrator pass** wires `envs/prod/main.tf`. |
| 2 | Yes, 2-way | T18 (promote script) and the `image-promote.yml` half of T17. |
| 3 | Yes, 2-way | `service` module and `jobs` module. T14 blocks on L3's result. |
| 4 | No | Sequential and interactive by nature. |
| 5 | Yes, 5-way | T15 edge, T16 filestore stub, T19 smoke test, T23+T24 docs, T25 alerts. Best parallelization opportunity in the whole plan. |
| 6 | No | Blocked on your fork/variant decision. |

**The one trap with parallel Terraform subagents.** Five agents writing modules
simultaneously is fine — each owns one directory under `infra/terraform/modules/`. What
is *not* fine is letting any of them touch `envs/prod/main.tf`, `versions.tf`, or
`variables.tf`, because they'll clobber each other. Every prompt below says so
explicitly. Wire the root module yourself, or in a single follow-up agent, once all five
finish.

---

## Phase L — Local validation

Prerequisites: Docker Desktop running, ~10 GB free disk. The image is multi-arch
(`linux/amd64` + `linux/arm64`), so it runs natively on Apple Silicon — no emulation.

### L1 — Build the local harness · Cursor

Do this one alone; everything else in Phase L depends on it.

```
Set up a local Docker Compose harness for validating a Paperclip deployment before we
put it on GCP Cloud Run. Create it under `local/` in this repo.

Context you need (I verified all of this against the upstream repo, don't re-derive it):
- Use the PUBLISHED image `ghcr.io/paperclipai/paperclip:sha-e55d702`. That tag is the
  v2026.722.0 release commit. It is public, multi-arch, and ~1.46 GB compressed. Do NOT
  build from source — the upstream build is a pnpm monorepo with four agent CLI
  toolchains and takes up to an hour.
- The container listens on port 3100. The image already sets HOST=0.0.0.0, which
  Paperclip's bind resolver maps to bind mode "lan". Entrypoint is docker-entrypoint.sh,
  which chowns $PAPERCLIP_HOME and drops to the `node` user via gosu.
- Paperclip's DB driver is postgres.js v3, called as `postgres(url)` with NO options
  object, so every connection parameter must live in the URL string.
- The server runs entirely from environment variables; the on-disk config.json is
  optional and the server never writes it on boot.

The goal of this harness is to prove Paperclip runs CORRECTLY STATELESS, which is our
Cloud Run design. So:
- Deliberately mount NO volume on /paperclip. That directory must stay ephemeral.
- Include a `postgres:17-alpine` service (user/password/db all `paperclip`) with a
  pg_isready healthcheck, and make the app depend on it being healthy.
- Include a MinIO service plus a one-shot `mc` init container that creates a bucket
  named `paperclip-uploads`. MinIO stands in for GCS, so we can exercise Paperclip's
  S3 storage provider path locally.

Write a `local/.env.example` with fixed (non-random) dev values so restarts are
reproducible, and have compose read from `local/.env`. Required variables:

  DATABASE_URL=postgres://paperclip:paperclip@db:5432/paperclip
  PORT=3100
  SERVE_UI=true
  PAPERCLIP_HOME=/paperclip
  PAPERCLIP_INSTANCE_ID=default
  PAPERCLIP_CONFIG=/paperclip/instances/default/config.json
  PAPERCLIP_DEPLOYMENT_MODE=authenticated
  PAPERCLIP_DEPLOYMENT_EXPOSURE=public
  PAPERCLIP_PUBLIC_URL=http://localhost:3100
  PAPERCLIP_API_URL=http://localhost:3100
  PAPERCLIP_MIGRATION_AUTO_APPLY=true
  PAPERCLIP_DB_BACKUP_ENABLED=false
  HEARTBEAT_SCHEDULER_ENABLED=true
  BETTER_AUTH_SECRET=<fixed 32-byte hex>
  PAPERCLIP_SECRETS_MASTER_KEY=<fixed 32-byte base64>
  PAPERCLIP_TOOL_ACTION_SIGNING_SECRET=<fixed 32-byte hex>
  PAPERCLIP_AGENT_JWT_SECRET=<fixed 32-byte hex>
  PAPERCLIP_STORAGE_PROVIDER=s3
  PAPERCLIP_STORAGE_S3_BUCKET=paperclip-uploads
  PAPERCLIP_STORAGE_S3_REGION=us-east-1
  PAPERCLIP_STORAGE_S3_ENDPOINT=http://minio:9000
  PAPERCLIP_STORAGE_S3_FORCE_PATH_STYLE=true
  PAPERCLIP_STORAGE_S3_PREFIX=uploads
  AWS_ACCESS_KEY_ID=minioadmin
  AWS_SECRET_ACCESS_KEY=minioadmin

Parameterize COMPOSE_PROJECT_NAME and the host port so several isolated stacks can run
side by side (later tests will need that).

Then bring it up and report back with:
1. Whether the server reaches a listening state, and how long from `up` to healthy.
2. Whether `GET /api/health` returns 200 and what its body contains.
3. Whether the startup log shows `plugin job coordinator started` and
   `plugin-loader: loadAll complete`.
4. CRITICALLY: whether `PAPERCLIP_DEPLOYMENT_EXPOSURE=public` rejects the plain-HTTP
   `PAPERCLIP_PUBLIC_URL=http://localhost:3100`. Public mode has stricter URL checks and
   this may fail. If it does, capture the exact error and tell me — do not paper over it
   by switching to `private`, because public is what we deploy with.
5. Peak memory used by the paperclip container (`docker stats`), since on Cloud Run the
   writable filesystem is tmpfs and counts against the memory limit.

Write findings to `local/FINDINGS.md`. Do not modify anything outside `local/`.
```

### L2 — Prove statelessness survives a restart · Cursor

Runs on L1's stack, right after. Don't parallelize this one.

```
Using the `local/` Compose harness, prove Paperclip's state survives a full container
replacement with an ephemeral /paperclip. This validates the core assumption of our
Cloud Run design.

Background: `server/src/secrets/local-encrypted-provider.ts` auto-generates a secrets
master key file when PAPERCLIP_SECRETS_MASTER_KEY is unset. With an ephemeral filesystem
that means a NEW key on every cold start, which would make every company secret already
in the database permanently undecryptable. Our harness sets the key explicitly. This test
proves that actually works.

Steps:
1. With the stack up, create some state through the UI or API: a company, an issue, and
   at least one uploaded file attachment.
2. Store a secret via Paperclip's secrets feature so we exercise the encrypted path.
3. `docker compose rm -sf` the paperclip container ONLY (leave postgres and minio),
   then bring it back up. This simulates a Cloud Run revision replacement.
4. Verify: the company/issue still exist, the uploaded file still downloads, and the
   stored secret still DECRYPTS.
5. Now the negative control: unset PAPERCLIP_SECRETS_MASTER_KEY, restart the container,
   and confirm the stored secret FAILS to decrypt. I want to see this failure mode with
   my own eyes so we know what it looks like.
6. Confirm the uploaded file physically landed in MinIO under the `uploads/` prefix, not
   on the container filesystem.

Append results to `local/FINDINGS.md` under a "Statelessness" heading. Restore the master
key in .env when you're done.
```

### L3 — First-admin bootstrap probe (was T2) · Cursor · **highest value in Phase L**

Can run in parallel with L4/L5 and L6 if given its own project name and port.

```
Resolve a documented contradiction in Paperclip about how the first admin is created in
`authenticated/public` mode. This blocks our GCP Phase 4 design, so I need an empirical
answer, not a reading of the docs.

The contradiction:
- `docs/deploy/aws-ecs.md` says "After the first user has signed up (which grants admin
  role), lock down the instance".
- `doc/DEPLOYMENT-MODES.md` section 8 says fresh authenticated installs sit in
  `bootstrap_pending` until the first instance_admin exists, that browser-based claim is
  DISABLED for `authenticated/public`, and that public deployments must use the
  high-entropy CLI bootstrap invite.

One of these is stale. Find out which, using the `local/` Compose harness (it is already
configured for authenticated/public).

Why this matters: Cloud Run has no `exec`. If the CLI invite is the only path, we need a
Cloud Run Job to run it. And there's a complication — `cli/src/commands/auth-bootstrap-ceo.ts`
calls `readConfig(configPath)` and bails with "No config found" if the file is absent,
then reads `config.server.deploymentMode` from THAT FILE rather than from the
environment. A stateless container has no such file. The registered CLI flags are only
--config, --data-dir, --force, --expires-hours, --base-url; there is no --db-url, so the
database comes from the DATABASE_URL env var.

Do this:
1. Against a completely fresh database, sign up a user through the UI. Does that user get
   instance_admin? Check the `instance_user_roles` table directly in postgres. Report
   which doc is correct.
2. Regardless of the answer, prove out the CLI path, because it's our Cloud Run design.
   Exec into the container and run:
       pnpm paperclipai auth bootstrap-ceo --base-url http://localhost:3100
   Confirm it fails on the missing config file.
3. Now write a minimal config.json to $PAPERCLIP_CONFIG and retry. Base the shape on the
   schema exercised in `server/src/__tests__/config-file.test.ts`. Note `$meta.source`
   must be `configure` — the reader rejects `edited-by-hand`. Starting point:
       {
         "$meta": {"version":1,"updatedAt":"<iso8601>","source":"configure"},
         "database": {"mode":"postgres","connectionString":"<DATABASE_URL>"},
         "logging": {"mode":"file"},
         "server": {"deploymentMode":"authenticated","deploymentExposure":"public",
                    "bind":"lan","port":3100}
       }
   Iterate against the actual zod schema until the CLI accepts it. Capture the EXACT
   working config.
4. Complete the flow end to end: accept the invite URL in a browser, confirm the user
   becomes instance_admin.
5. Verify PAPERCLIP_AUTH_DISABLE_SIGN_UP=true then blocks new signups while the invite
   flow still works.

Deliverables: the exact working config.json saved to
`config/bootstrap-config.template.json` with placeholders, and a step-by-step account in
`local/FINDINGS.md` under "First-admin bootstrap". This becomes the spec for the
Cloud Run Job in T14.
```

### L4 — Migration fail-fast behaviour · Cursor

Pair with L5 in one subagent.

```
Verify Paperclip's boot-time migration behaviour so we can choose the right Cloud Run
posture. Use the `local/` Compose harness with its own COMPOSE_PROJECT_NAME and port
offset so it doesn't collide with other running stacks.

Background from `server/src/index.ts`, function `promptApplyMigrations`, which resolves
in this exact order:
    1. PAPERCLIP_MIGRATION_AUTO_APPLY=true        -> apply
    2. PAPERCLIP_MIGRATION_PROMPT=never           -> refuse to start
    3. non-TTY (which Cloud Run always is)        -> apply
So the DEFAULT Cloud Run behaviour is a silent auto-migration on every cold start. We
don't want that — we want migrations in a controlled Job and a service that fails fast on
a stale schema. Prove the mechanism does what we think.

Tests:
1. Fresh empty database + PAPERCLIP_MIGRATION_AUTO_APPLY=true -> migrations apply,
   server starts. Record how long the migration phase takes; on Cloud Run the startup
   probe budget is capped at 240 seconds total, so this number decides whether the Job
   is merely preferable or mandatory.
2. Fresh empty database, AUTO_APPLY unset, PAPERCLIP_MIGRATION_PROMPT=never -> the server
   must REFUSE to start with a message about pending migrations. Capture the exact error
   and the exit code.
3. Same as 2 but with an already-migrated database -> must start normally.
4. Confirm no TTY is attached in these runs (that's Cloud Run's condition), so we're
   testing the real code path.

Append to `local/FINDINGS.md` under "Migrations".
```

### L5 — Prove the migration job command · Cursor

Same subagent as L4.

```
Determine the exact command our Cloud Run `paperclip-db-migrate` Job should run, using
the published image `ghcr.io/paperclipai/paperclip:sha-e55d702`.

Candidate is `pnpm --filter @paperclipai/db migrate`, which maps to
`tsx src/migrate.ts` and is preceded by a `check:migrations` step
(see packages/db/package.json). Unknowns to settle empirically:
- Are dev dependencies present in the production image? The Dockerfile runs
  `pnpm install --frozen-lockfile` in a `deps` stage built FROM `base`, which does NOT
  set NODE_ENV, so dev deps probably ARE installed — but the final `production` stage
  does set NODE_ENV=production. Verify tsx and drizzle-kit actually resolve at runtime.
- Does the entrypoint interfere? It chowns $PAPERCLIP_HOME and gosu's to `node`.
- Working directory should be /app.

Run the container with an entrypoint/command override against the local postgres and
confirm migrations apply cleanly to an empty database, and that a second run is a no-op.
If the pnpm path doesn't work, find one that does (e.g. invoking tsx directly on
packages/db/src/migrate.ts) and document it.

Also: read the image's OCI labels `io.github.paperclipai.schema.last-migration` and
`io.github.paperclipai.schema.migration-count` (use `docker inspect` or `crane config`)
and record their values for sha-e55d702. Our CI will gate deploys on these.

Deliverable: the exact working command + env, in `local/FINDINGS.md` under
"Migration job". This is the spec for the Cloud Run Job in T11.
```

### L6 — WebSockets and shutdown behaviour (was T12 + T13) · Cursor

Own subagent, own project name.

```
Characterize Paperclip's realtime and shutdown behaviour against two Cloud Run
constraints. Use the `local/` harness with its own COMPOSE_PROJECT_NAME and port offset.

Constraint 1 — Cloud Run caps any connection at the request timeout, max 3600s, and
kills all connections on a revision change. Paperclip has WebSocket endpoints in
`server/src/realtime/live-events-ws.ts` and
`server/src/realtime/environment-custom-image-terminal-ws.ts`.

Constraint 2 — Cloud Run gives roughly 10 seconds of SIGTERM grace. Paperclip's
`server/src/index.ts` implements a heartbeat-run drain on shutdown that plainly expects
longer.

Tests:
1. Open the UI, confirm the live-events WebSocket connects. Kill the connection
   server-side (restart the container) and observe: does the UI reconnect automatically,
   show an error, or silently stop updating? Silent staleness is the dangerous outcome —
   flag it loudly if that's what happens.
2. Send SIGTERM to the container and time how long it takes to exit cleanly. If it
   exceeds ~10s, that's a real finding: Cloud Run will SIGKILL mid-drain on every deploy.
3. Concurrency probe for the heartbeat scheduler. The scheduler is a plain `setInterval`
   in index.ts with in-memory in-flight tracking, and `services/heartbeat.ts` has NO
   pg advisory lock and no leader election. On Cloud Run, max-instances is per-revision,
   so a traffic migration briefly runs two schedulers. Start TWO app containers against
   the SAME postgres, both with HEARTBEAT_SCHEDULER_ENABLED=true, let them run through
   several scheduler intervals, and determine whether heartbeat runs get double-claimed.
   Inspect the `heartbeat_runs` table for duplicates. Report whether the claim path is
   idempotent in practice.

Append to `local/FINDINGS.md` under "Realtime and shutdown". Test 3 is the one that
decides whether our rollout strategy needs to be more careful than a normal Cloud Run
traffic migration.
```

### L7 — Sizing check · You (5 minutes)

With L1's stack running and some activity in the UI:

1. `docker stats` on the paperclip container. Watch RSS while browsing and uploading.
2. `docker exec <container> df -h /paperclip` — how much is written to the ephemeral
   filesystem. On Cloud Run that's tmpfs and counts against the memory limit.
3. `docker exec <container> du -sh /paperclip/*` to see what's growing.

If steady-state RSS + `/paperclip` usage clears 3 GB, bump the Cloud Run memory to 8 GiB
in the plan before Phase 3, rather than discovering it as an OOM'd revision.

### L8 — Review findings and adjust · You

Read `local/FINDINGS.md`. Three findings can change the plan and are worth pausing on:

- If **L1 item 4** shows public mode rejects plain HTTP: harmless locally (Cloud Run is
  HTTPS), but it means all local testing must run behind an HTTPS proxy or in `private`
  mode. Note the divergence.
- If **L3** shows first-signup grants admin: Phase 4 collapses to "sign up, then disable
  signup", T14 disappears, and risk R1 is closed.
- If **L6 test 3** shows double-claimed heartbeat runs: R3 escalates. Rollouts then need
  a deliberate drain — deploy the new revision with `HEARTBEAT_SCHEDULER_ENABLED=false`,
  migrate traffic, then flip the flag — instead of a plain traffic migration.

---

## Phase 0 — GCP foundation

### T1 — Confirm the version pin · You

Decide between `sha-e55d702` (v2026.722.0, latest stable release) and a newer master
commit. Recommendation: stay on the release. Upstream ships roughly weekly CalVer, and
master carries unreleased changes. Record the choice in the repo README.

Only reason to reconsider: if you want the `cloud` variant in Phase 6 without forking,
you'd have to move to a master commit — see section 0.

### T3 — Create the GCP project · You

1. `gcloud projects create <PROJECT_ID> --name="Paperclip"` (or use the console).
2. Link billing: `gcloud billing projects link <PROJECT_ID> --billing-account=<ACCOUNT_ID>`.
3. Pick a region and keep it consistent everywhere — Cloud Run, Cloud SQL, Artifact
   Registry, and the GCS bucket should all share it. `us-central1` unless you have a
   latency or data-residency reason otherwise.
4. Decide the hostname now (e.g. `paperclip.yourdomain.com`); it feeds
   `PAPERCLIP_PUBLIC_URL`, the managed certificate, and the Better Auth trusted origins.
5. Set a budget alert on the project. With `min-instances=1` and always-allocated CPU
   this service bills continuously — see risk R10.

### T7 — Author the GCP bootstrap script · Cursor

Can run in parallel with T3.

```
Write `scripts/bootstrap-gcp.sh` — the one-time, manually-run script that creates
everything Terraform itself needs before it can run. It must be idempotent (safe to
re-run) and must never create service-account JSON keys.

It takes PROJECT_ID, REGION, GITHUB_REPO (owner/name), and STATE_BUCKET as inputs, via
flags or environment, and validates all of them up front.

What it does:
1. Enable APIs: run, sqladmin, artifactregistry, secretmanager, compute,
   servicenetworking, iam, iamcredentials, cloudresourcemanager, storage,
   certificatemanager, logging, monitoring.
2. Create the Terraform state GCS bucket with versioning ON, uniform bucket-level
   access, and public access prevention enforced.
3. Create a Workload Identity Federation pool and an OIDC provider for GitHub Actions.
   Constrain the attribute condition to THIS repository — a provider that trusts all of
   GitHub is a well-known privilege-escalation footgun.
4. Create a `terraform-deployer` service account, grant it the project roles Terraform
   needs (be specific and minimal — not Owner), and bind it to the WIF provider via
   roles/iam.workloadIdentityUser scoped to the repo.
5. Print, at the end, the exact GitHub repository secrets/variables I need to add:
   the workload identity provider resource name, the service account email, project id,
   region, and state bucket.

Use `set -euo pipefail`, guard every create with an existence check, and echo what it's
doing. Also write `docs/gcp-bootstrap.md` recording what the script creates and how to
tear it down.

Do not run the script — I'll run it myself against my project.
```

### T8 — Run bootstrap and wire GitHub · You

1. Authenticate: `gcloud auth login && gcloud config set project <PROJECT_ID>`.
2. Run `./scripts/bootstrap-gcp.sh` with your values. Read its output.
3. In GitHub → repo → Settings → Secrets and variables → Actions, add the values it
   printed (`GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`,
   `TF_STATE_BUCKET`). These are variables, not secrets, except where noted — none of
   them are credentials, which is the point of WIF.
4. Create a GitHub Environment named `prod` with required reviewers (yourself). The apply
   workflow gates on it.

### T20 — DNS · You

Do this early even though it's used in Phase 5 — managed certificate provisioning can
take up to an hour and you don't want it on the critical path.

1. Decide whether the hostname lives in Cloud DNS or your existing provider.
2. If Cloud DNS: create the zone and delegate the subdomain with NS records at your
   registrar.
3. If staying external: just confirm you can add A/AAAA records when Phase 5 needs them.

---

## Phase 1 — Terraform foundation

### T6 — Scaffold the repository tree · Cursor

Must complete before the parallel module work.

```
Create the directory structure for this deployment repository. Per my convention, do it
by writing `scripts/scaffold-dirs.sh` and then running that script — not with ad-hoc
mkdir commands.

Target tree:

  .github/workflows/
  infra/terraform/modules/{network,database,registry,secrets,storage,service,jobs,edge}/
  infra/terraform/envs/{prod,staging}/
  config/
  scripts/
  docs/
  local/

The script must be idempotent and place a `.gitkeep` in any directory that would
otherwise be empty.

Also create at the root:
- `infra/terraform/versions.tf` pinning hashicorp/google ~> 6.0 and required_version
  >= 1.9.
- `.gitignore` covering .terraform/, *.tfstate*, *.tfvars (but NOT *.tfvars.example),
  .env, and local/FINDINGS.md scratch output.
- A README section stating which Paperclip version this repo deploys
  (v2026.722.0 / ghcr.io/paperclipai/paperclip:sha-e55d702) and that Paperclip source is
  intentionally NOT vendored here.
```

### T9 — Terraform modules · Cursor · **5 parallel subagents**

Launch these five together. Shared preamble — paste it at the top of each of the five
prompts:

```
SHARED CONTEXT (applies to all five module tasks):
We're deploying Paperclip (an agent-orchestration control plane) to GCP Cloud Run,
stateless, single-instance. Provider hashicorp/google ~> 6.0, Terraform >= 1.9.
Region and project come from variables, never hardcoded.

BOUNDARY RULE — IMPORTANT: You own EXACTLY ONE directory under
infra/terraform/modules/. Do not create or edit anything in infra/terraform/envs/,
infra/terraform/versions.tf, or any other module's directory. Four other agents are
working in parallel and will clobber each other otherwise. Root-module wiring happens
in a separate integration pass.

Every module needs main.tf, variables.tf, outputs.tf, and a README.md documenting
inputs, outputs, and any manual steps.
```

**Agent 1 — network**

```
[SHARED CONTEXT]

Build `infra/terraform/modules/network/`.

- A VPC with no auto-created subnets.
- One subnet sized /26 or larger, dedicated to Cloud Run Direct VPC egress. Direct VPC
  egress requires a /26 minimum; document why in the README so nobody shrinks it later.
- A Private Service Access reserved IP range plus the servicenetworking VPC peering, so
  Cloud SQL can get a private IP.
- NO Cloud NAT. We configure Cloud Run with PRIVATE_RANGES_ONLY egress, meaning private
  traffic goes over the VPC to Cloud SQL while public traffic (Anthropic, OpenAI, GitHub)
  exits Cloud Run directly. This deliberately saves the ~$35/mo NAT charge — note it in
  the README so it isn't "fixed" by someone adding a NAT later.
- Firewall rules following least privilege.
- lifecycle prevent_destroy on the PSA range and peering: destroying them orphans the
  Cloud SQL private IP and is painful to recover from.

Outputs: network id/self_link, subnet id/self_link, PSA range name.
```

**Agent 2 — database**

```
[SHARED CONTEXT]

Build `infra/terraform/modules/database/`.

- Cloud SQL for PostgreSQL, version POSTGRES_17 (matching upstream Paperclip's
  docker-compose, which uses postgres:17).
- PRIVATE IP ONLY — ipv4_enabled = false, private_network pointing at the VPC from the
  network module (accept it as a variable). Depends on the PSA peering existing.
- Automated backups enabled with point-in-time recovery (WAL archiving) and 7-day
  retention, matching upstream's RDS reference.
- deletion_protection = true AND lifecycle prevent_destroy.
- Tier as a variable, defaulting to db-custom-1-3840. Document db-g1-small as the
  cheaper small-team option in the README.
- maintenance window and insights configuration as variables.
- Create the `paperclip` database and the `paperclip` user. The password comes IN as a
  variable (sourced from Secret Manager by the caller) — do NOT generate it here and do
  NOT output it.

Outputs: instance connection name, PRIVATE IP address, database name, user name.
Never output the password.

README must document the DATABASE_URL shape the app needs:
  postgresql://paperclip:<pw>@<private-ip>:5432/paperclip?sslmode=require
and flag that Paperclip's driver is postgres.js called as `postgres(url)` with no
options object, so every connection parameter must be in that string.
```

**Agent 3 — registry**

```
[SHARED CONTEXT]

Build `infra/terraform/modules/registry/`.

- An Artifact Registry DOCKER repository named `paperclip` in the configured region.
  Same region as Cloud Run — cross-region pulls measurably worsen cold start, and our
  image is ~1.46 GB compressed.
- A cleanup policy: keep the most recent N versions (variable, default 10) and delete
  untagged images older than 30 days.
- IAM: grant roles/artifactregistry.reader to the Cloud Run runtime service account
  (accept the email as a variable) and roles/artifactregistry.writer to the CI deployer
  service account.
- Optionally enable vulnerability scanning behind a variable.

Outputs: repository id, and the full repository URL prefix
(REGION-docker.pkg.dev/PROJECT/paperclip) so callers can build image references.
```

**Agent 4 — secrets**

```
[SHARED CONTEXT]

Build `infra/terraform/modules/secrets/`.

CRITICAL DESIGN RULE: this module manages secret CONTAINERS, IAM, and replication only.
It must NEVER contain, generate, or accept plaintext secret VALUES. Values are seeded
out-of-band via `gcloud secrets versions add`, so no plaintext ever enters Terraform
state or git. Use `lifecycle { ignore_changes = [...] }` where needed so applies don't
fight manually-added versions.

Create these secrets (make the list a variable with these as the default):
  paperclip-db-password
  paperclip-database-url
  paperclip-better-auth-secret
  paperclip-secrets-master-key
  paperclip-tool-action-signing-secret
  paperclip-agent-jwt-secret
  paperclip-decision-signing-secret
  paperclip-gcs-hmac-access-key
  paperclip-gcs-hmac-secret
  paperclip-anthropic-api-key
  paperclip-openai-api-key
  paperclip-github-token

Per-secret IAM: grant roles/secretmanager.secretAccessor to the Cloud Run runtime
service account ON EACH SECRET INDIVIDUALLY. Do not grant a project-level role.

`paperclip-secrets-master-key` gets special treatment: lifecycle prevent_destroy, and a
prominent README warning. Every company secret Paperclip stores is encrypted with it —
if it's lost or rotated without a re-encryption plan, all of them become permanently
undecryptable. Document that it must be excluded from routine rotation.

Use automatic replication unless a region variable is set.

Outputs: a map of secret name -> secret id, for the service module to build
value_source.secret_key_ref wiring.
```

**Agent 5 — storage**

```
[SHARED CONTEXT]

Build `infra/terraform/modules/storage/`.

Background: Paperclip stores uploads through a pluggable provider. Its S3 provider
(`server/src/storage/s3-provider.ts`) constructs `new S3Client({region, endpoint,
forcePathStyle})` with NO explicit credentials, so it uses the default AWS SDK chain —
i.e. AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY. We exploit that: point it at GCS's
S3-compatible XML API with an HMAC key. Only Put, Get, Head, and Delete are used, all of
which GCS supports.

Create:
- A GCS bucket for uploads: uniform bucket-level access, versioning on, public access
  prevention enforced, a lifecycle rule to purge noncurrent versions after N days
  (variable), and the same region as everything else.
- A DEDICATED service account for HMAC access, with roles/storage.objectAdmin scoped to
  THIS BUCKET ONLY via a bucket IAM member — no project-level storage role.
- A google_storage_hmac_key for that service account.

SECURITY NOTE for the README: google_storage_hmac_key writes its secret into Terraform
state. Document that the state bucket must be private with restricted IAM, and offer the
alternative of creating the HMAC key out-of-band and referencing it only by Secret
Manager name. Make that alternative selectable with a `create_hmac_key` boolean.

Outputs: bucket name, bucket location, HMAC access id, and the HMAC secret marked
`sensitive = true`.

The README must spell out the exact env vars the app needs:
  PAPERCLIP_STORAGE_PROVIDER=s3
  PAPERCLIP_STORAGE_S3_BUCKET=<bucket>
  PAPERCLIP_STORAGE_S3_ENDPOINT=https://storage.googleapis.com
  PAPERCLIP_STORAGE_S3_FORCE_PATH_STYLE=true
  PAPERCLIP_STORAGE_S3_REGION=<must match bucket location for SigV4 credential scope>
  AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY = the HMAC pair
```

### T9b — Integration pass · Cursor (single agent, after all five finish)

```
The five Terraform foundation modules under infra/terraform/modules/ are complete. Wire
them into the prod root module. You own infra/terraform/envs/prod/ and
infra/terraform/versions.tf — the module directories are done, don't restructure them.

Create:
- envs/prod/backend.tf: GCS backend, bucket from the bootstrap script.
- envs/prod/main.tf: instantiate network, database, registry, secrets, storage with
  correct inter-module wiring and explicit depends_on where the graph isn't sufficient
  (PSA peering must exist before Cloud SQL).
- envs/prod/variables.tf and terraform.tfvars.example (never a real .tfvars).
- envs/prod/outputs.tf surfacing what later phases need: Cloud SQL private IP, bucket
  name, registry URL, secret ids.
- Mirror the structure into envs/staging/ with smaller defaults.

Then run `terraform fmt -recursive`, `terraform init -backend=false`, and
`terraform validate` in both envs and fix anything that fails. Do NOT run plan or apply
against real GCP — I'll do that.
```

### T10 — Seed secret values · You + Cursor

First, the script:

```
Write `scripts/seed-secrets.sh`. It generates and uploads values for the Secret Manager
secrets created by the secrets module. Idempotent, and it must never print secret values
to stdout or write them to disk.

- Generate with `openssl rand`: 32-byte hex for better-auth-secret,
  tool-action-signing-secret, agent-jwt-secret, decision-signing-secret; 32-byte base64
  for secrets-master-key (Paperclip accepts base64, hex, or a raw 32-char string); a
  strong alphanumeric db password.
- Prompt interactively for values that come from elsewhere: the Anthropic/OpenAI/GitHub
  keys, and the GCS HMAC pair.
- Compose paperclip-database-url from the db password plus a Cloud SQL private IP passed
  in as an argument.
- Before adding a version, check whether one already exists and require an explicit
  --force to overwrite. For paperclip-secrets-master-key, refuse to overwrite AT ALL
  without a separate --i-understand-this-destroys-all-stored-secrets flag, and explain
  why in the refusal message.
- Print only secret NAMES and version numbers when done.
```

Then run it yourself, after the Phase 1 apply produces the Cloud SQL private IP. **Back
up `paperclip-secrets-master-key` to your password manager before anything writes data.**

### T4 / T5 — Prove the connection string and GCS interop · Cursor

After the Phase 1 apply. These two are independent — run as 2 subagents.

```
Prove the exact DATABASE_URL string works against our real Cloud SQL instance before we
bake it into Secret Manager.

Why this needs proving rather than assuming: Paperclip's DB layer is
`packages/db/src/client.ts`, which calls `postgres(url)` — postgres.js v3 with NO options
object. No SSL config, no pool tuning. Everything must be expressible in the URL, and
whether postgres.js v3 honours `?sslmode=require` from a connection string needs
confirming, not assuming.

Steps:
1. Get the Cloud SQL private IP from terraform output.
2. From a context that can reach the VPC (a temporary Cloud Run Job using the Paperclip
   image is the most faithful test, since it exercises the exact driver — a Compute
   Engine VM in the subnet also works), connect using:
       postgresql://paperclip:<pw>@<private-ip>:5432/paperclip?sslmode=require
3. Confirm the connection succeeds AND that TLS is actually in use — query
   `SELECT * FROM pg_stat_ssl WHERE pid = pg_backend_pid();` and check the ssl column.
   If sslmode is silently ignored, say so plainly; private IP inside the VPC is our
   fallback, but I want to know which we're relying on.
4. Test the fallback shape too: Cloud SQL's Unix socket via the built-in connector,
   `postgres://user:pass@/paperclip?host=/cloudsql/<connection-name>`.

Report the exact working string in `docs/runbook.md` under "Database connection".
```

```
Prove Paperclip's S3 storage provider works against real GCS via the S3-compatible XML
API, using the HMAC key our storage module created.

Why: `server/src/storage/s3-provider.ts` builds `new S3Client({region, endpoint,
forcePathStyle})` with no explicit credentials, so it picks up AWS_ACCESS_KEY_ID /
AWS_SECRET_ACCESS_KEY. It uses exactly four operations — PutObject, GetObject,
HeadObject, DeleteObject.

The specific risk is the SigV4 credential scope: the AWS SDK signs with a region, and
GCS validates it against the bucket location. Getting this wrong produces confusing
403s.

Steps:
1. Write a small Node script using @aws-sdk/client-s3 that mirrors the provider's exact
   client construction, and run all four operations against the real bucket with
   endpoint https://storage.googleapis.com and forcePathStyle true.
2. Determine the correct PAPERCLIP_STORAGE_S3_REGION value empirically. Try the bucket's
   actual location (e.g. us-central1), then `auto`, then us-east-1. Record which work.
3. Test with a prefix set, since we run with PAPERCLIP_STORAGE_S3_PREFIX=uploads.
4. Test a file large enough to trigger multipart in the SDK, to see whether GCS's XML API
   handles it — Paperclip uses plain PutObject, but the SDK may still switch strategies.

Report the exact working env-var values in `docs/runbook.md` under "Object storage", and
flag anything that only worked with a non-obvious setting.
```

### T21 — Approve the first apply · You

```
cd infra/terraform/envs/prod
terraform init
terraform plan -out=tfplan
# read it properly — especially anything marked destroy
terraform apply tfplan
```

Then run `scripts/seed-secrets.sh` with the Cloud SQL private IP from the outputs.

---

## Phase 2 — Image supply chain

Two parallel subagents.

### T18 — Image promotion script · Cursor

```
Write `scripts/promote-image.sh`, which mirrors a Paperclip image from GHCR into our
Artifact Registry and resolves it to an immutable digest.

Facts I verified, so you don't have to rediscover them:
- Upstream publishes to ghcr.io/paperclipai/paperclip. It is PUBLIC — anonymous pulls
  work, no credentials needed.
- There are NO version tags. Only `latest`, `latest-cloud`, `buildcache*`, and
  `sha-<short>` tags. Our pin is `sha-e55d702`, which is the v2026.722.0 release commit.
- Images carry OCI labels `io.github.paperclipai.schema.last-migration` and
  `io.github.paperclipai.schema.migration-count`, published specifically so deploy
  tooling can check schema compatibility without pulling the image.

The script should:
1. Take a source ref (default sha-e55d702) and target project/region/repo.
2. Use `crane copy` (or gcrane) rather than docker pull/push — it's a registry-to-registry
   copy, so it's fast and preserves the multi-arch index. Include an install check for
   crane with a helpful message.
3. Copy to REGION-docker.pkg.dev/PROJECT/paperclip/paperclip:<version-label>.
4. Resolve and print the resulting sha256 DIGEST. The digest is what everything else
   pins to; tags are never used in deploy config.
5. Read the two schema labels via `crane config` and print them.
6. Emit machine-readable output (JSON or GITHUB_OUTPUT format) so CI can consume it.

Also handle the fallback path with a --build-from-source flag that documents (but does
not by default run) building from a source checkout — needed only if we ever want the
`--target cloud` variant, which upstream does NOT publish for release commits.
```

### T17a — Image promotion workflow · Cursor

```
Write `.github/workflows/image-promote.yml`.

Trigger: workflow_dispatch with a `paperclip_ref` input, default `sha-e55d702`.

Auth: google-github-actions/auth@v2 using Workload Identity Federation. NO service
account JSON keys — the WIF provider and deployer SA come from repo variables
(GCP_WIF_PROVIDER, GCP_DEPLOYER_SA, GCP_PROJECT_ID, GCP_REGION). Set the job's
`permissions:` to `id-token: write` and `contents: write`.

Steps:
1. Authenticate to GCP, configure docker auth for Artifact Registry.
2. Run scripts/promote-image.sh with the requested ref.
3. Capture the resolved digest and the two schema labels.
4. Open a PULL REQUEST (peter-evans/create-pull-request or gh CLI) that updates the
   pinned `image_digest` in infra/terraform/envs/prod/terraform.tfvars.example and
   wherever else it's referenced. The PR body must include: source ref, resolved digest,
   both schema label values, and a diff of migration-count versus the currently deployed
   value.

Rationale to put in a comment at the top of the file: version bumps become reviewable
diffs instead of mutable-tag drift, and the migration-count delta tells the reviewer how
much schema change is inbound.

Pin all third-party actions to a full commit SHA, not a tag.
```

---

## Phase 3 — Service and jobs

Two parallel subagents (T11 splits cleanly), then T14 which depends on L3's findings.

### T11a — Cloud Run service module · Cursor

```
Build `infra/terraform/modules/service/` — the Cloud Run v2 service for Paperclip.

BOUNDARY: you own only this module directory. Another agent is building modules/jobs/ in
parallel. Don't touch envs/.

Configuration, with the reasoning so you don't "optimize" any of it away:

- google_cloud_run_v2_service. Container port 3100 (the image sets ENV PORT=3100 and
  EXPOSES 3100; its HOST=0.0.0.0 maps to Paperclip's "lan" bind mode, which is correct).
- Image is an INPUT VARIABLE and must be a digest reference, never a tag.
- Resources: cpu "2", memory "4Gi" (both variables; upstream's reference deployment uses
  2 vCPU / 4 GB).
- CPU ALWAYS ALLOCATED (cpu_idle = false). Non-negotiable: Paperclip's heartbeat
  scheduler is a plain setInterval, so with CPU throttling it freezes between requests
  and agents never wake.
- startup_cpu_boost = true — the image is ~1.46 GB compressed.
- scaling: min_instance_count = 1, max_instance_count = 1. The scheduler has no advisory
  lock or leader election and WebSocket state is per-process, so this is a CORRECTNESS
  requirement, not a cost choice. Put that in a comment.
- timeout = 3600s (the platform max) so live-event WebSockets survive as long as possible.
- session_affinity = true.
- Startup probe: HTTP GET /api/health. Note in a comment that Cloud Run caps
  failureThreshold * periodSeconds at 240s, which is why migrations run in a separate Job.
- Liveness probe: HTTP GET /api/health with a generous period. /api/health returns 200
  unauthenticated and redacts detail for non-board/agent actors, so it's probe-safe.
- vpc_access with a network_interface on our subnet and egress = PRIVATE_RANGES_ONLY.
- A dedicated runtime service account with ONLY: per-secret secretmanager.secretAccessor
  (granted in the secrets module), logging.logWriter, cloudtrace.agent. No project-level
  roles.

Environment: split plain env vars from secret-backed ones using
value_source.secret_key_ref for the latter. Plain:
  SERVE_UI=true, PAPERCLIP_HOME=/paperclip, PAPERCLIP_INSTANCE_ID=default,
  PAPERCLIP_CONFIG=/paperclip/instances/default/config.json,
  PAPERCLIP_DEPLOYMENT_MODE=authenticated, PAPERCLIP_DEPLOYMENT_EXPOSURE=public,
  PAPERCLIP_PUBLIC_URL, PAPERCLIP_API_URL, PAPERCLIP_ALLOWED_HOSTNAMES,
  PAPERCLIP_BIND=lan, PAPERCLIP_MIGRATION_PROMPT=never,
  PAPERCLIP_DB_BACKUP_ENABLED=false, HEARTBEAT_SCHEDULER_ENABLED=true,
  PAPERCLIP_SECRETS_STRICT_MODE=true, PAPERCLIP_AUTH_DISABLE_SIGN_UP (variable,
  default false for initial bootstrap), and the six PAPERCLIP_STORAGE_S3_* vars.
Secret-backed:
  DATABASE_URL, BETTER_AUTH_SECRET, PAPERCLIP_SECRETS_MASTER_KEY,
  PAPERCLIP_TOOL_ACTION_SIGNING_SECRET, PAPERCLIP_AGENT_JWT_SECRET,
  PAPERCLIP_DECISION_SIGNING_SECRET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
  and optionally ANTHROPIC_API_KEY, OPENAI_API_KEY, GITHUB_TOKEN.

Deliberately DO NOT set PAPERCLIP_TRUSTED_MCP_RUNTIME_HOST — leaving it unset makes local
stdio MCP runtime slots fail closed, which is the correct posture for a public deployment.

ingress as a variable, defaulting to INGRESS_TRAFFIC_ALL, so Phase 5 can flip it to
INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER once the ALB exists.

README documenting every variable and, importantly, why min=max=1.
```

### T11b — Cloud Run jobs module · Cursor

```
Build `infra/terraform/modules/jobs/` — two Cloud Run v2 Jobs sharing the service's image
digest and secret wiring, differing by command override.

BOUNDARY: you own only this module directory. Another agent is building modules/service/
in parallel. Don't touch envs/.

Job 1: `paperclip-db-migrate`
- Runs the Paperclip migration entrypoint. The command comes from a variable; the
  expected value is `pnpm --filter @paperclipai/db migrate` at working directory /app,
  but a local test (see local/FINDINGS.md, "Migration job") establishes the exact
  verified command — read that file and use what it says if it's present.
- Needs DATABASE_URL from Secret Manager and VPC access to reach Cloud SQL private IP.
- task_count 1, parallelism 1, max_retries 0. A half-retried migration is worse than a
  failed one.
- Generous timeout (variable, default 1800s).

Job 2: `paperclip-auth-bootstrap`
- Mints the first-admin invite URL for authenticated/public deployments, which is the
  only sanctioned bootstrap path in that mode.
- Complication: cli/src/commands/auth-bootstrap-ceo.ts requires an on-disk config.json at
  $PAPERCLIP_CONFIG and reads server.deploymentMode from that FILE, not from the
  environment. A stateless container has none. So this job's command must first write a
  minimal config.json, then run
  `pnpm paperclipai auth bootstrap-ceo --base-url <public-url>`.
- Read `config/bootstrap-config.template.json` for the verified config shape (produced by
  the local L3 test). If that file doesn't exist yet, make the config content a variable
  and say so clearly in the README.
- Needs DATABASE_URL and the same secret set as the service.
- The invite URL is printed to stdout, i.e. Cloud Logging. Document how to retrieve it.

Both jobs take the image digest as a variable and use the same runtime service account
as the service.
```

### T14 — Bootstrap job content · Cursor

Blocked on L3. If L3 showed first-signup grants admin, skip this and delete Job 2.

```
Finalize the `paperclip-auth-bootstrap` Cloud Run Job using what we learned locally.
Read `local/FINDINGS.md` (section "First-admin bootstrap") and
`config/bootstrap-config.template.json` first — they contain the verified procedure.

Produce:
1. The exact config.json content the job writes, with values templated from environment
   variables ($DATABASE_URL, $PAPERCLIP_PUBLIC_URL). Remember $meta.source must be
   "configure"; the config reader rejects "edited-by-hand".
2. The complete command/args for the job's container, as a shell -c invocation that
   writes the config then runs bootstrap-ceo.
3. A section in `docs/runbook.md` titled "First admin bootstrap" covering: how to execute
   the job, how to find the invite URL in Cloud Logging (with the exact gcloud logging
   read command), how to accept it, and how to then set
   PAPERCLIP_AUTH_DISABLE_SIGN_UP=true and roll a new revision.
4. The documented fallback: deploy one revision with
   PAPERCLIP_DEPLOYMENT_EXPOSURE=private, restrict reach via Cloud Armor to my IP, claim
   the instance in the browser, then roll forward to public. Include when to reach for it.

Update infra/terraform/modules/jobs/ accordingly.
```

### T17b — Terraform and deploy workflows · Cursor

```
Write the three remaining GitHub Actions workflows. All use Workload Identity Federation
via google-github-actions/auth@v2 — no service account JSON keys anywhere. Repo variables
available: GCP_PROJECT_ID, GCP_REGION, GCP_WIF_PROVIDER, GCP_DEPLOYER_SA, TF_STATE_BUCKET.
Pin every third-party action to a full commit SHA.

1. `terraform-plan.yml` — on pull_request touching infra/**. Runs fmt -check, init,
   validate, tflint, tfsec (or trivy config), then plan. Posts the plan as a PR comment.
   Read-only credentials. permissions: id-token write, pull-requests write, contents read.

2. `terraform-apply.yml` — on push to main touching infra/**. Re-plans then applies,
   gated on the `prod` GitHub Environment with required reviewers. A concurrency group so
   two applies never overlap.

3. `deploy.yml` — on push to main that changes the pinned image digest, plus
   workflow_dispatch. Sequence:
     a. Execute the paperclip-db-migrate Cloud Run Job at the new digest; wait for
        completion; FAIL THE DEPLOY on a non-zero result.
     b. terraform apply the service module at the new digest.
     c. Smoke test via scripts/smoke-test.sh.
     d. On failure, roll traffic back to the previous revision.
   IMPORTANT — put this in a comment: schema rollback is NOT automatic. Migrations are
   forward-only, so a traffic rollback can leave a newer schema in place. The runbook
   must be consulted for anything beyond a trivial revert.
   Concurrency group shared with terraform-apply, since the service is single-instance.
```

---

## Phase 4 — First admin bootstrap · You

Sequential and interactive; no parallelization.

1. Confirm the service is serving: `curl -sf https://<domain>/api/health`.
2. Check the `commit` field in that response matches the commit you pinned. The image
   populates it from `PAPERCLIP_BUILD_COMMIT`, so it's a genuine check that the running
   binary is what you think.
3. Execute the bootstrap job:
   `gcloud run jobs execute paperclip-auth-bootstrap --region <REGION> --wait`
4. Retrieve the invite URL from logs:
   ```
   gcloud logging read \
     'resource.type=cloud_run_job AND resource.labels.job_name=paperclip-auth-bootstrap' \
     --limit 50 --format='value(textPayload)'
   ```
5. Open the invite URL in a browser, create your account, accept. Verify you have
   instance_admin.
6. Harden: set `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` in the tfvars, apply, and confirm a
   new revision rolls out.
7. Verify signups are now blocked and the invite flow still works for adding teammates.

If the job path fails, fall back to the private-exposure browser claim documented in T14.

---

## Phase 5 — Edge, hardening, observability

**Five parallel subagents.** The biggest parallelization win in the plan — these touch
disjoint files.

### T15 — Edge module · Cursor

```
Build `infra/terraform/modules/edge/`, gated behind an `enable_load_balancer` variable so
it can be adopted independently.

BOUNDARY: you own only this module directory. Four other agents are working elsewhere in
this repo in parallel.

- Global external Application Load Balancer with a serverless NEG pointing at our Cloud
  Run service.
- Google-managed SSL certificate for the configured hostname.
- HTTP to HTTPS redirect.
- A Cloud Armor security policy: rate limiting on /api/auth/* (Paperclip enables Better
  Auth rate limiting itself in public mode, but a front-door limiter is defense in depth),
  an optional IP allowlist variable, and the preconfigured OWASP rules as an opt-in
  variable.
- Once the LB exists, Cloud Run ingress should flip to
  INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER. The service module already exposes ingress as a
  variable — just document the ordering dependency in the README; don't edit that module.
- WebSocket support matters: Paperclip uses WS for live events and terminals. Confirm and
  document the backend timeout setting needed to support long-lived connections, and make
  it a variable defaulting to 3600s to match the Cloud Run request timeout.

README should note the cheaper alternative — Cloud Run custom domain mapping, no LB, no
WAF — and when that's the right call.
```

### T16 — Filestore escape hatch · Cursor

```
Add a variable-gated Filestore option so we can later switch from stateless to a
persistent /paperclip without restructuring the Terraform.

BOUNDARY: create `infra/terraform/modules/filestore/` only. Do not edit modules/service/;
instead document the exact snippet a caller adds to the service module's volume/
volume_mounts blocks.

Context: upstream Paperclip's reference cloud deployment mounts EFS at /paperclip for the
secrets master key, uploads, instance config, and agent workspaces. We deliberately went
stateless instead — Cloud SQL, GCS, and Secret Manager cover the first three, and agent
workspaces are accepted as ephemeral because we run control-plane-only. This module exists
in case that decision reverses.

- google_filestore_instance behind `enable_filestore`, defaulting to FALSE and creating
  nothing when off.
- Document the real costs in the README: ~1 TiB minimum for Basic HDD (~$200+/mo), and it
  pins the service to a single zone.
- Document the NFS volume + volume_mount snippet for Cloud Run.
- IMPORTANT WARNING for the README: the Paperclip image's docker-entrypoint.sh runs a
  recursive chown over $PAPERCLIP_HOME whenever it finds a file not owned by `node`. On a
  freshly-mounted NFS share that is a full-tree chown on first boot and can be slow enough
  to blow the 240s startup probe budget. Note the mitigation (pre-seed ownership, or a
  longer startup probe on first deploy).
- Also document why GCS FUSE was rejected: no POSIX file locking, and that same recursive
  chown is pathological on gcsfuse.
```

### T19 — Smoke test · Cursor

```
Write `scripts/smoke-test.sh`, used by the deploy workflow as the post-deploy gate and by
me for manual verification.

Takes a base URL and an expected commit SHA. Checks, in order, failing fast with a clear
message:
1. GET /api/health returns 200 within a timeout.
2. The `commit` field in that response equals the expected SHA. The Paperclip image
   populates it from the PAPERCLIP_BUILD_COMMIT build arg, so this genuinely verifies the
   running binary — not just that something is up.
3. The login page renders (public deployments are authenticated, so expect an auth screen,
   not the dashboard).
4. Recent Cloud Logging entries contain both documented healthy-startup markers:
   `plugin job coordinator started` and `plugin-loader: loadAll complete`.
5. No 5xx in the last N minutes of logs.
6. The WebSocket endpoint accepts an upgrade (a simple handshake check is enough).

Exit non-zero with an actionable message on any failure. Support a --verbose flag. Make
the Cloud Logging checks skippable with a flag so the script also works against the local
Compose stack.
```

### T23 + T24 — Documentation · Cursor

```
Write `docs/runbook.md` and `docs/upgrade.md` for this Paperclip GCP deployment. Read
.cursor/plans/paperclip-deployment.md and local/FINDINGS.md first — most of the substance
is already there; your job is to turn it into operational procedure.

BOUNDARY: create only these two files under docs/. Other agents are working elsewhere.

docs/runbook.md must cover:
- Normal deploy procedure and what each workflow does.
- Rollback. Be explicit that traffic rollback does NOT roll back the schema — migrations
  are forward-only, so a reverted revision may face a newer schema. Give the decision
  procedure for when that's safe.
- First-admin bootstrap (may already be drafted by another task — merge, don't duplicate).
- SECRETS MASTER KEY RECOVERY. The most important section. Every company secret Paperclip
  stores is encrypted with PAPERCLIP_SECRETS_MASTER_KEY. If it's lost, they're
  unrecoverable — Cloud SQL backups don't contain it. Cover: where it's backed up, how to
  restore it, and why it must be excluded from routine rotation.
- Database restore from Cloud SQL backup / PITR, including the fact that the master key
  must be restored alongside it.
- Scale to zero for cost saving, and the consequence: agents don't wake while scaled down.
- Incident triage: where logs are, what the healthy startup markers are, what a failed
  startup probe looks like, what an OOM looks like.
- Known operational quirks: WebSockets drop on every revision change; ~10s SIGTERM grace
  means in-flight work is interrupted on deploy; single instance means no zero-downtime
  deploys.

docs/upgrade.md must cover:
- How to bump the pinned Paperclip version, end to end.
- That upstream publishes NO version tags on GHCR — only `latest` and `sha-<short>` — so
  you map a release tag to its commit and use `sha-<short7>`.
- How to read the migration-count delta from the image's OCI schema labels and what
  makes a bump risky.
- The pre-upgrade checklist: read upstream release notes, take a manual Cloud SQL backup,
  check for breaking env-var changes.
- That the `cloud` image variant is NOT published for release commits, and what that
  means if we ever need it.
```

### T25 — Alerting · Cursor

```
Add Cloud Monitoring alerting as Terraform under `infra/terraform/modules/monitoring/`.

BOUNDARY: create only this module directory. Four other agents are working in parallel
elsewhere in this repo.

Alert policies, each with a notification channel passed in as a variable:
1. Cloud Run 5xx rate above a threshold over 5 minutes.
2. Container restart / revision failure.
3. Memory utilization above 80%. This one matters more than usual: Cloud Run's writable
   filesystem is tmpfs and counts against the memory limit, and Paperclip writes agent
   workspaces and logs to /paperclip.
4. Cloud SQL connection count approaching the instance maximum.
5. Cloud SQL disk utilization above 80%.
6. A log-based metric and alert for startup FAILURES — specifically the "Refusing to
   start against a stale schema" message, which is our fail-fast migration guard firing.
7. Absence of the healthy startup markers after a deploy.
8. Cloud SQL backup failure.

Also add a Cloud Monitoring dashboard showing request rate, latency, instance count,
memory, and DB connections.

Keep all thresholds as variables with sensible defaults.
```

---

## Phase 6 — Agent execution backend

### T26 — Decide the execution backend · You

Blocked on the fork question from section 0. Three options, in the order I'd consider
them:

1. **HTTP adapters only** — no sandbox provider, no cloud image variant, no fork. Agents
   run wherever their HTTP endpoint lives. Simplest; check whether it covers your intended
   workflows.
2. **Daytona via a master-commit cloud image** — pick one of the 109 commits that has both
   variants. You give up "latest stable" pinning.
3. **Fork and build `--target cloud` at your pinned release tag** — the only way to get a
   stable, digest-pinned cloud variant. Costs you a fork to maintain and a real build
   pipeline (multi-arch, four CLI toolchains, ~60 min upstream).

Also procure Daytona (or equivalent) credentials if you go that route.

### T27 — Wire the execution backend · Cursor

Write this prompt once T26 is decided — its content depends entirely on which option you
pick. The shape:

```
Wire up remote agent execution for our Cloud Run Paperclip deployment using <CHOSEN
BACKEND>.

Context: we run control-plane-only. Cloud Run hosts the API, UI, and scheduler; agent
execution happens elsewhere. The `cloud` image variant (Dockerfile `--target cloud`)
bundles sandbox-provider plugins and expects a `plugins.autoInstall` key list delivered
through PAPERCLIP_MANAGED_CONFIG; bundled plugin install is handled by
server/src/services/bundled-plugins.ts and requires each plugin's dist/ to exist in the
image.

Tasks:
1. Add the provider credentials as Secret Manager secrets and wire them into the service
   module.
2. Set PAPERCLIP_MANAGED_CONFIG with the appropriate plugins.autoInstall list.
3. Update the pinned image to the cloud variant <SPECIFIC DIGEST>.
4. Keep PAPERCLIP_TRUSTED_MCP_RUNTIME_HOST UNSET so local stdio MCP keeps failing closed.
5. Verify end to end: trigger an agent run and confirm execution happens on the remote
   sandbox, not inside the Cloud Run container.
6. Document the whole thing in docs/runbook.md.
```

---

## Quick reference — task to owner and prompt location

| Task | Phase | Owner | Where |
|---|---|---|---|
| L1 harness | L | cursor | §Phase L / L1 |
| L2 statelessness | L | cursor | §Phase L / L2 |
| L3 bootstrap probe (was T2) | L | cursor | §Phase L / L3 |
| L4 migration fail-fast | L | cursor | §Phase L / L4 |
| L5 migration job command | L | cursor | §Phase L / L5 |
| L6 websockets + shutdown (was T12/T13) | L | cursor | §Phase L / L6 |
| L7 sizing | L | me | §Phase L / L7 |
| L8 review findings | L | me | §Phase L / L8 |
| T1 version pin | 0 | me | §Phase 0 / T1 |
| T3 GCP project | 0 | me | §Phase 0 / T3 |
| T7 bootstrap script | 0 | cursor | §Phase 0 / T7 |
| T8 run bootstrap, wire GitHub | 0 | me | §Phase 0 / T8 |
| T20 DNS | 0 | me | §Phase 0 / T20 |
| T6 scaffold | 1 | cursor | §Phase 1 / T6 |
| T9 five modules | 1 | cursor ×5 | §Phase 1 / T9 |
| T9b integration | 1 | cursor | §Phase 1 / T9b |
| T10 seed secrets | 1 | cursor + me | §Phase 1 / T10 |
| T4 connection string | 1 | cursor | §Phase 1 / T4 |
| T5 GCS interop | 1 | cursor | §Phase 1 / T5 |
| T21 first apply | 1 | me | §Phase 1 / T21 |
| T18 promote script | 2 | cursor | §Phase 2 / T18 |
| T17a promote workflow | 2 | cursor | §Phase 2 / T17a |
| T11a service module | 3 | cursor | §Phase 3 / T11a |
| T11b jobs module | 3 | cursor | §Phase 3 / T11b |
| T14 bootstrap job | 3 | cursor | §Phase 3 / T14 |
| T17b remaining workflows | 3 | cursor | §Phase 3 / T17b |
| T22 first-admin claim | 4 | me | §Phase 4 |
| T15 edge | 5 | cursor | §Phase 5 / T15 |
| T16 filestore stub | 5 | cursor | §Phase 5 / T16 |
| T19 smoke test | 5 | cursor | §Phase 5 / T19 |
| T23+T24 docs | 5 | cursor | §Phase 5 / T23+T24 |
| T25 alerting | 5 | cursor | §Phase 5 / T25 |
| T26 execution backend decision | 6 | me | §Phase 6 / T26 |
| T27 wire execution backend | 6 | cursor | §Phase 6 / T27 |
