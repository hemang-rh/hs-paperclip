# Paperclip on GCP — Cost-optimized execution plan (high level)

Working plan. Supersedes the chat revision of the original
[paperclip-execution-guide.md](paperclip-execution-guide.md) for *what we are
building now*. Paperclip-on-Cloud-Run facts in the original guide still apply.

Date: 2026-08-16

**Apply path:** GitHub Actions only. You do not run `terraform apply` locally.
You approve the GitHub Environment; CI plans and applies.

**One-time exception:** you run `scripts/bootstrap-gcp.sh` once so Terraform and
Actions have a state bucket and Workload Identity. That bootstrap cannot be
Terraform-managed.

---

## Target

```text
Paperclip (Cloud Run)
    → adapter
    → LiteLLM (Cloud Run)
         → Gemini Flash / Flash-Lite   worker (default)
         → Gemini Pro                  reasoning
         → Claude                      premium escalation
Codex CLI where Paperclip already supports it
No GPU / vLLM / OSS until Phase 5 data justifies it
```

First milestone: Phase 1 + Phase 2 (Gemini `worker` only).

---

## Phase map

```text
DONE   Phase L   Local validation — do not redo
YOU    Phase 0   GCP project + one-time CI bootstrap (WIF, state bucket)
CI     Phase 1   Paperclip + Cloud SQL + secrets + GCS   (Actions apply)
CI     Phase 2   LiteLLM + Gemini worker                 ← first milestone
       Phase 3   Agent aliases (3–5 agents)
       Phase 4   Deterministic worker → reasoning → premium
       Phase 5   Cost telemetry (simple BigQuery)
       Phase 6   Fewer LLM calls
LATER  Phase 7–8 OSS go/no-go
```

---

## Phase 0 — GCP account and CI bootstrap

Goal: billed project plus everything GitHub Actions needs. No app infrastructure yet.

| Task | Owner |
|---|---|
| 0.1 Create/select project, set `PROJECT_ID` / region | You |
| 0.2 Link billing, monthly budget + 50/75/90/100% alerts | You |
| 0.3 `gcloud auth login` + application-default credentials | You |
| 0.4 Confirm no GPU / no GKE | You |
| 0.5 Write `scripts/bootstrap-gcp.sh`: enable APIs, TF state bucket, WIF pool+provider constrained to this repo, `terraform-deployer` SA (no JSON keys) | Cursor |
| 0.6 Run the bootstrap script | You |
| 0.7 Add GitHub Actions variables (`GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`, `TF_STATE_BUCKET`) and a GitHub Environment `dev` with required reviewers (you) | You |

CI workflows themselves are written in Phase 1 (they need the Terraform tree). Bootstrap must exist first.

---

## Phase 1 — Paperclip foundation (CI applies)

Goal: UI up, Postgres durable, secrets in Secret Manager. No LiteLLM yet.

| Task | Owner |
|---|---|
| 1.1 Scaffold `infra/`, `gateway/`, `scripts/`, `.github/workflows/` in this repo (do not vendor Paperclip source) | Cursor |
| 1.2 Terraform: APIs, Artifact Registry, VPC + private Cloud SQL (small dev tier), Secret Manager containers, GCS uploads, runtime SAs (`paperclip-runtime`, `litellm-runtime` placeholder) | Cursor |
| 1.3 Image promote script + `image-promote.yml` (mirror GHCR → Artifact Registry, digest pin, PR that updates the pin) | Cursor |
| 1.4 Cloud Run `paperclip`: 1 vCPU / 4 GiB, CPU always on, min=max=1, auto-migrate, Cloud SQL + GCS + secrets | Cursor |
| 1.5 Bootstrap Job (`auth bootstrap-ceo` + seeded `config.json`) | Cursor |
| 1.6 GitHub Actions: `terraform-plan.yml` (PR), `terraform-apply.yml` (merge to main, Environment `dev` gate), `deploy.yml` (new image digest → apply service → smoke). WIF auth, no SA JSON keys. | Cursor |
| 1.7 Seed secret **values** out of band (Paperclip secrets now; model keys in Phase 2). Not Terraform. | You |
| 1.8 Open/merge the infra PR; **approve the `dev` Environment** so Actions applies | You |
| 1.9 Dispatch image-promote (or merge its pin PR); claim first admin; disable signup | You |
| 1.10 Validate: UI, company, restart, data still there, logs have no secrets | You |

You never run `terraform apply`. Review the plan comment on the PR, then approve the Environment.

Default agents may fail until Phase 2 (`claude_local` with no key). Expected.

---

## Phase 2 — LLM gateway (first milestone)

Same apply path: Cursor lands Terraform/config in a PR; Actions applies after you approve.

| Task | Owner |
|---|---|
| 2.1 Gemini auth: API key (faster) vs Vertex IAM (later) | You |
| 2.2 Put Gemini (and optional Anthropic) keys in Secret Manager; do not paste them into chat | You |
| 2.3 LiteLLM Cloud Run + aliases `worker` / `reasoning` / `premium`; gateway auth; no public anonymous API | Cursor |
| 2.4 Inspect Paperclip for an existing HTTP/OpenAI adapter; reuse if it works; custom `litellm-http` only if needed | Cursor |
| 2.5 Merge PR; approve Environment; confirm Actions applied LiteLLM | You |
| 2.6 Point one test agent at `worker` | You |
| 2.7 Validate: Paperclip → LiteLLM → Gemini; Claude not default; no keys in Paperclip logs | You |

---

## Phase 3 — Agent routing

| Task | Owner |
|---|---|
| 3.1 Roster of 3–5 agents (purpose, default alias, fallback) | You |
| 3.2 Config layer: alias, token/iteration caps, no auto-classifier | Cursor |
| 3.3 Configure those agents; run 10–20 real tasks | You |

Developer → Codex uses Paperclip’s existing adapter. No Daytona.

---

## Phase 4 — Escalation

| Task | Owner |
|---|---|
| 4.1 Approve triggers and bounded retries | You |
| 4.2 Implement `worker → reasoning → premium` only; no extra LLM to decide | Cursor |
| 4.3 Force failures; confirm no infinite loop | You |

---

## Phase 5 — Cost observability

| Task | Owner |
|---|---|
| 5.1 Confirm KPIs (cost per successful task) | You |
| 5.2 Structured usage logs (no prompts/secrets) | Cursor |
| 5.3 Cheap BigQuery sink + queries | Cursor |
| 5.4 Simplest GCP dashboard | Cursor |
| 5.5 Weekly review | You |

---

## Phase 6 — Fewer calls

| Task | Owner |
|---|---|
| 6.1 Turn off useless heartbeats | You |
| 6.2 Guardrails: max iterations / tools / tokens / runtime | Cursor |
| 6.3 Low-risk context trimming after measuring prompts | Cursor |

---

## Phases 7–8 — later

Not scheduled. You decide from Phase 5 data. Cursor does not create GPUs unless you say so.

---

## Still not in this plan

- ALB / Cloud Armor / Filestore
- Dedicated migrate Cloud Run Job (auto-apply is enough for v1)
- Vendoring or rebuilding Paperclip
- Daytona / `-cloud` image / fork
- prod + staging (one `dev` env, one GitHub Environment)
- Scale-to-zero (`min-instances = 0`)
- Local `terraform apply`

---

## What you still do by hand (not Terraform)

These cannot go through Actions apply:

1. GCP project, billing, budget
2. One-time `bootstrap-gcp.sh` (state bucket + WIF)
3. GitHub variables + Environment reviewers
4. Secret **values** into Secret Manager
5. Approve the GitHub Environment (that *is* the apply button)
6. First-admin invite in the browser
7. Quality / cost / OSS go-no-go
