# Paperclip on GCP — Cost-optimized execution plan (high level)

Working plan: **why and constraints**. Task done/not-done lives only in [`STATUS.md`](../../STATUS.md). Update that file when a task finishes.

Supersedes the chat revision of the original
[paperclip-execution-guide.md](paperclip-execution-guide.md) for *what we are
building now*. Paperclip-on-Cloud-Run facts in the original guide still apply.

Date: 2026-08-16

**Apply path:** GitHub Actions only. You do not run `terraform apply` locally.
You approve the GitHub Environment; CI plans and applies.

**One-time exception:** you run `scripts/bootstrap-gcp.sh` once so Terraform and
Actions have a state bucket and Workload Identity. That bootstrap cannot be
Terraform-managed. The script is already in the repo (STATUS 0.5).

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

Tasks, owners, and checkboxes: [`STATUS.md`](../../STATUS.md).

---

## Phase 0 — GCP account and CI bootstrap

Billed project plus everything GitHub Actions needs. No app infrastructure yet.

CI workflows are written in Phase 1 (they need the Terraform tree). The bootstrap
script already exists; do not rewrite it. You still run it once (0.6) after the
project and billing exist.

---

## Phase 1 — Paperclip foundation (CI applies)

UI up, Postgres durable, secrets in Secret Manager. No LiteLLM yet.

Consume the published image (digest-pinned). Do not vendor or rebuild Paperclip.
Keep **min-instances = 1** and **CPU always allocated** so the heartbeat scheduler
runs. Use auto-migrate for v1. GCS holds uploads; Secret Manager holds
`PAPERCLIP_SECRETS_MASTER_KEY` and auth secrets.

You never run `terraform apply`. Review the plan comment on the PR, then approve
the `dev` Environment.

Default agents may fail until Phase 2 (`claude_local` with no key). Expected.

---

## Phase 2 — LLM gateway (first milestone)

Same apply path: Cursor lands Terraform/config in a PR; Actions applies after you
approve. Provider keys live on LiteLLM, not on Paperclip. Reuse a built-in
HTTP/OpenAI adapter if Paperclip already has one.

Stop until Gemini `worker` is reliable before starting Phase 3.

---

## Phase 3 — Agent routing

Three to five agents, logical aliases, no automatic complexity classifier.
Developer → Codex uses Paperclip’s existing adapter. No Daytona.

---

## Phase 4 — Escalation

Deterministic `worker → reasoning → premium` only. Bounded retries. No extra LLM
request to decide whether to escalate.

---

## Phase 5 — Cost observability

Structured usage logs (no prompts/secrets), a cheap BigQuery sink, simplest GCP
dashboard. Primary KPI: cost per successfully completed task.

---

## Phase 6 — Fewer calls

Cut useless heartbeats, then guardrails, then low-risk context trimming after
measuring current prompts.

---

## Phases 7–8 — later

Not scheduled. You decide from Phase 5 data. Cursor does not create GPUs unless
you say so.

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
