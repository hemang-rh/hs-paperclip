# hs-paperclip

GCP deployment for [Paperclip](https://github.com/paperclipai/paperclip). This repo does **not** vendor Paperclip source. It consumes the published image `ghcr.io/paperclipai/paperclip:sha-e55d702` (v2026.722.0).

## Start here

1. **[`STATUS.md`](STATUS.md)** — where we are and every task (the only checklist).
2. **[`.cursor/plans/paperclip-cost-optimized-execution.md`](.cursor/plans/paperclip-cost-optimized-execution.md)** — working plan: target architecture, constraints, what we are not building.
3. **[`local/README.md`](local/README.md)** — local Compose harness. Phase L findings: `local/FINDINGS-L*.md`.

Older docs ([deployment plan](.cursor/plans/paperclip-deployment.md), [original execution guide](.cursor/plans/paperclip-execution-guide.md), [cost-optimized runbook](docs/Paperclip-GCP-Cost-Optimized-Deployment-Execution-Runbook.md)) are background. Do not treat them as the task list.

## Current target

Paperclip on Cloud Run → adapter → LiteLLM → Gemini Flash (default) / Gemini Pro / Claude (premium only). CI via GitHub Actions applies Terraform. No GPU until usage data says otherwise.

## Layout

| Path | Purpose |
|---|---|
| `STATUS.md` | Task tracker |
| `local/` | Docker Compose validation harness |
| `scripts/bootstrap-gcp.sh` | One-time GCP bootstrap for Terraform + Actions (Phase 0.5, already written) |
| `docs/` | Bootstrap notes and architecture runbook |
| `config/` | Bootstrap `config.json` template for first admin |
| `infra/` | Terraform (Phase 1; not created yet) |
