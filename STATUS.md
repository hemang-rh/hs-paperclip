# Status

**Single task tracker** for this repo. Do not keep a second checklist.

Working plan (why / constraints): [`.cursor/plans/paperclip-cost-optimized-execution.md`](.cursor/plans/paperclip-cost-optimized-execution.md)

## You are here

| | |
|---|---|
| Current phase | **0 — GCP account and CI bootstrap** |
| Next task | **0.1** Create/select GCP project, set `PROJECT_ID` / region (**You**) |
| First milestone | Phase 1 + Phase 2 (Gemini `worker`) |
| Do not redo | Phase L. Do not rewrite `scripts/bootstrap-gcp.sh` (0.5 is done). |

When a task finishes, mark it `[x]` in this file in the same change set. Completing work without updating this file is incomplete.

---

## Phase L — Local validation

Done. Do not rerun. Evidence is in `local/`.

- [x] **L1** Local Compose harness (published image, no volume on `/paperclip`) — Cursor — `local/docker-compose.yml`, `local/README.md`
- [x] **L2** Statelessness / secrets master key — Cursor — details were captured during local validation
- [x] **L3** First-admin bootstrap probe — Cursor — `local/FINDINGS-L3.md`, `config/bootstrap-config.template.json`
- [x] **L4** Migration fail-fast — Cursor — `local/FINDINGS-L45.md`
- [x] **L5** Migration job command — Cursor — `local/FINDINGS-L45.md`
- [x] **L6** WebSockets, SIGTERM, dual-scheduler — Cursor — `local/FINDINGS-L6.md`
- [x] **L7** Sizing — You — `local/FINDINGS-L7.md` (~2 GiB peak; keep 4 GiB Cloud Run)
- [x] **L8** Review findings — You — bootstrap Job required; migrate Job not mandatory for v1; min=1 / CPU always on

---

## Phase 0 — GCP account and CI bootstrap

Goal: billed project plus everything GitHub Actions needs. No app infrastructure yet.

- [ ] **0.1** Create/select GCP project, set `PROJECT_ID` / region — **You**
- [ ] **0.2** Link billing, monthly budget + 50/75/90/100% alerts — **You**
- [ ] **0.3** `gcloud auth login` + application-default credentials — **You**
- [ ] **0.4** Confirm no GPU / no GKE — **You**
- [x] **0.5** Write `scripts/bootstrap-gcp.sh` (APIs, TF state bucket, WIF locked to this repo, deployer SA, no JSON keys) — Cursor — `scripts/bootstrap-gcp.sh`, `docs/gcp-bootstrap.md`
- [ ] **0.6** Run the bootstrap script — **You**
- [ ] **0.7** GitHub Actions variables (`GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`, `TF_STATE_BUCKET`) and Environment `dev` with you as required reviewer — **You**

CI workflows are Phase 1 (they need the Terraform tree). Bootstrap script must exist first — it does.

---

## Phase 1 — Paperclip foundation (CI applies)

Goal: UI up, Postgres durable, secrets in Secret Manager. No LiteLLM yet. You never run `terraform apply`.

- [ ] **1.1** Scaffold `infra/`, `gateway/`, `scripts/`, `.github/workflows/` (do not vendor Paperclip source) — Cursor
- [ ] **1.2** Terraform: APIs, Artifact Registry, VPC + private Cloud SQL (small dev tier), Secret Manager containers, GCS uploads, runtime SAs (`paperclip-runtime`, `litellm-runtime` placeholder) — Cursor
- [ ] **1.3** Image promote script + `image-promote.yml` (GHCR → Artifact Registry, digest pin, pin PR) — Cursor
- [ ] **1.4** Cloud Run `paperclip`: 1 vCPU / 4 GiB, CPU always on, min=max=1, auto-migrate, Cloud SQL + GCS + secrets — Cursor
- [ ] **1.5** Bootstrap Job (`auth bootstrap-ceo` + seeded `config.json`) — Cursor
- [ ] **1.6** GitHub Actions: `terraform-plan.yml`, `terraform-apply.yml` (Environment `dev` gate), `deploy.yml`. WIF, no SA JSON keys — Cursor
- [ ] **1.7** Seed Paperclip secret values out of band (model keys in Phase 2) — **You**
- [ ] **1.8** Merge infra PR; approve Environment `dev` so Actions applies — **You**
- [ ] **1.9** Dispatch image-promote (or merge pin PR); claim first admin; disable signup — **You**
- [ ] **1.10** Validate: UI, company, restart, data persists, logs have no secrets — **You**

Default agents may fail until Phase 2 (`claude_local` with no key). Expected.

---

## Phase 2 — LLM gateway (first milestone)

- [ ] **2.1** Gemini auth: API key (faster) vs Vertex IAM (later) — **You**
- [ ] **2.2** Put Gemini (and optional Anthropic) keys in Secret Manager; do not paste into chat — **You**
- [ ] **2.3** LiteLLM Cloud Run + aliases `worker` / `reasoning` / `premium`; gateway auth; no public anonymous API — Cursor
- [ ] **2.4** Reuse Paperclip HTTP/OpenAI adapter if it exists; custom `litellm-http` only if needed — Cursor
- [ ] **2.5** Merge PR; approve Environment; confirm Actions applied LiteLLM — **You**
- [ ] **2.6** Point one test agent at `worker` — **You**
- [ ] **2.7** Validate: Paperclip → LiteLLM → Gemini; Claude not default; no keys in Paperclip logs — **You**

---

## Phase 3 — Agent routing

- [ ] **3.1** Roster of 3–5 agents (purpose, default alias, fallback) — **You**
- [ ] **3.2** Config layer: alias, token/iteration caps, no auto-classifier — Cursor
- [ ] **3.3** Configure those agents; run 10–20 real tasks — **You**

Developer → Codex uses Paperclip’s existing adapter. No Daytona.

---

## Phase 4 — Escalation

- [ ] **4.1** Approve triggers and bounded retries — **You**
- [ ] **4.2** Implement `worker → reasoning → premium` only; no extra LLM to decide — Cursor
- [ ] **4.3** Force failures; confirm no infinite loop — **You**

---

## Phase 5 — Cost observability

- [ ] **5.1** Confirm KPIs (cost per successful task) — **You**
- [ ] **5.2** Structured usage logs (no prompts/secrets) — Cursor
- [ ] **5.3** Cheap BigQuery sink + queries — Cursor
- [ ] **5.4** Simplest GCP dashboard — Cursor
- [ ] **5.5** Weekly review — **You**

---

## Phase 6 — Fewer calls

- [ ] **6.1** Turn off useless heartbeats — **You**
- [ ] **6.2** Guardrails: max iterations / tools / tokens / runtime — Cursor
- [ ] **6.3** Low-risk context trimming after measuring prompts — Cursor

---

## Phases 7–8 — later (not scheduled)

Do not start until Phase 5 has real usage data. Do not create GPUs unless **You** say so.

- [ ] **7.1** Identify high-volume, simple, latency-tolerant candidate tasks — **You**
- [ ] **7.2** Benchmark harness (Gemini worker vs future OSS endpoint; no GPUs yet) — Cursor
- [ ] **7.3** Select 2–3 OSS candidates from actual workload — **You**
- [ ] **7.4** Temporary Cloud Run GPU benchmark (only after explicit approval) — Cursor
- [ ] **7.5** Run benchmark; **You** judge quality — You + Cursor
- [ ] **8.1** OSS production go / no-go — **You**
