# Paperclip AI on GCP — Cost-Optimized Deployment & Execution Runbook

> **Not the task tracker.** Done/not-done is [`STATUS.md`](../STATUS.md). Working
> plan (CI apply, what we dropped) is
> [`.cursor/plans/paperclip-cost-optimized-execution.md`](../.cursor/plans/paperclip-cost-optimized-execution.md).
> This runbook is architecture and detailed prompts; ignore “run terraform apply
> locally” — GitHub Actions applies.

## 1. Objective

Build a cost-optimized Paperclip AI platform on Google Cloud where:

```text
Paperclip AI
      │
      ▼
Agent / Model Adapter
      │
      ▼
LLM Gateway — LiteLLM
      │
      ├──── Gemini Flash / Flash-Lite   ← DEFAULT
      │
      ├──── Gemini Pro                  ← REASONING
      │
      └──── Claude                      ← PREMIUM ESCALATION
          
Coding Agents
      │
      └──── Codex CLI / ChatGPT subscription where applicable
```

Initially:

- No GPU.
- No vLLM.
- No self-hosted OSS model.
- Gemini Flash-class models handle most routine workloads.
- Gemini Pro handles difficult reasoning.
- Claude is an escalation model.
- Codex handles software-engineering-focused agents.
- OSS inference is introduced only after actual usage shows that it is cheaper.

Paperclip itself is a Node.js/React application. Its project documentation recommends using an external PostgreSQL database for production instead of the embedded local database.

---

# 2. Ownership Model

| Type of activity | Owner |
|---|---|
| Architecture decisions | Me |
| GCP account/project decisions | Me |
| Billing and budget decisions | Me |
| API keys / credentials | Me |
| Terraform | Cursor |
| Docker | Cursor |
| Cloud Run configuration | Cursor |
| Cloud SQL configuration | Cursor |
| LiteLLM configuration | Cursor |
| Paperclip adapter implementation | Cursor |
| Routing logic | Cursor |
| Tests | Cursor |
| Observability implementation | Cursor |
| Quality acceptance | Me |
| Cost acceptance | Me |
| OSS model go/no-go | Me |

The guiding rule throughout the implementation is:

> **I approve infrastructure, models, credentials, quality and cost. Cursor implements and automates.**

---

# 3. Global Variables

Before starting, decide on the following values.

```text
PROJECT_ID=<your-gcp-project>
REGION=<your-gcp-region>
ENVIRONMENT=dev

PAPERCLIP_SERVICE=paperclip
GATEWAY_SERVICE=llm-gateway

ARTIFACT_REPO=paperclip-platform

DATABASE_NAME=paperclip
DATABASE_USER=paperclip_app

GEMINI_WORKER_ALIAS=worker
GEMINI_REASONING_ALIAS=reasoning
CLAUDE_PREMIUM_ALIAS=premium
```

Keep Cloud Run and Cloud SQL in the same region where practical to reduce latency and unnecessary networking complexity.

---

# 4. Cursor Global Safety Prompt

Use this once when starting the Cursor project.

## Cursor Prompt

```text
You are acting as the implementation engineer for my Paperclip AI platform on Google Cloud.

The platform will eventually contain:

- Paperclip AI
- Google Cloud Run
- Artifact Registry
- Cloud SQL PostgreSQL
- Secret Manager
- LiteLLM
- Gemini
- Anthropic Claude
- Paperclip custom HTTP/API adapter if required
- cost observability
- optional OSS inference later

Implementation principles:

1. Infrastructure must be defined using Terraform wherever practical.
2. Never hard-code API keys, passwords, tokens, project secrets or credentials.
3. Use Google Secret Manager for application secrets.
4. Use variables for PROJECT_ID, REGION and environment.
5. Prefer least-privilege service accounts.
6. Keep dev and production configuration separate.
7. Do not create GPUs, GKE clusters or OSS inference infrastructure unless explicitly requested.
8. Do not execute destructive Terraform operations.
9. Before modifying existing project files, inspect the repository.
10. Preserve existing Paperclip code unless a modification is necessary.
11. When modifying Paperclip itself, keep custom integrations isolated so future Paperclip upgrades are manageable.
12. Add tests for new functionality.
13. After every implementation task, provide:
    - files created
    - files modified
    - commands I need to execute
    - validation steps
    - assumptions made
14. Do not run terraform apply automatically.
15. Do not commit credentials or .env files containing secrets.

First inspect the repository and report its current structure. Do not modify anything yet.
```

---

# PHASE 1 — Deploy Paperclip Foundation

## Goal

Establish:

```text
Internet
   │
   ▼
Paperclip
Cloud Run
   │
   ▼
Cloud SQL
PostgreSQL
```

Paperclip's repository currently includes a Dockerfile and supports external PostgreSQL for production deployments.

Cloud Run supports deploying immutable revisions from container images, with Artifact Registry being Google's recommended registry.

---

## Phase 1 Task List

| Task | Owner |
|---|---|
| 1.1 Create/select GCP project | Me |
| 1.2 Configure billing and budget | Me |
| 1.3 Authenticate gcloud | Me |
| 1.4 Create repository structure | Cursor |
| 1.5 Create Terraform foundation | Cursor |
| 1.6 Create Artifact Registry | Cursor |
| 1.7 Create service accounts | Cursor |
| 1.8 Create Cloud SQL PostgreSQL | Cursor |
| 1.9 Containerize/validate Paperclip | Cursor |
| 1.10 Deploy Paperclip to Cloud Run | Cursor |
| 1.11 Validate Paperclip | Me |

---

## Task 1.1 — Create/select GCP project

**Owner: Me**

### Steps

1. Open Google Cloud Console.
2. Create a dedicated project or select the project you want Paperclip to run within.
3. Record the Project ID.

Then locally:

```bash
gcloud projects create paperclip-ks-prod --name="Paperclip"

gcloud billing accounts list
# copy the ACCOUNT_ID of the billing account you want to charge

gcloud billing projects link paperclip-ks-prod \
  --billing-account=XXXXXX-XXXXXX-XXXXXX

gcloud config set project paperclip-ks-prod
gcloud config set run/region us-west1
gcloud config set compute/region us-west1

# Application Default Credentials, which Terraform reads
gcloud auth application-default login
gcloud auth application-default set-quota-project paperclip-ks-prod
```

```bash
gcloud config set project <PROJECT_ID>
```

Verify:

```bash
gcloud config get-value project
```

---

## Task 1.2 — Configure billing and budget

**Owner: Me**

### Steps

1. Confirm billing is enabled for the project.
2. Open Billing → Budgets & alerts.
3. Create an initial monthly budget.
4. Configure alerts such as:
   - 50%
   - 75%
   - 90%
   - 100%
5. Do not enable GPU resources yet.

---

## Task 1.3 — Authenticate gcloud

**Owner: Me**

Run:

```bash
gcloud auth login
```

Then:

```bash
gcloud auth application-default login
```

Confirm:

```bash
gcloud projects describe <PROJECT_ID>
```

---

## Task 1.4 — Repository structure

**Owner: Cursor**

### Cursor Prompt

```text
Create the initial repository structure for the Paperclip platform.

Target structure:

paperclip-platform/
  README.md
  docs/
    architecture.md
    deployment.md
    cost-strategy.md
  infra/
    terraform/
      modules/
      environments/
        dev/
        prod/
  paperclip/
  gateway/
  adapters/
  agents/
  observability/
  scripts/

Requirements:

- Do not add application secrets.
- Add .gitignore entries for Terraform state, .env files and credentials.
- Create a README explaining the purpose of each directory.
- Create docs/architecture.md with the target architecture:
  Paperclip -> adapter -> LiteLLM -> Gemini Flash / Gemini Pro / Claude.
- Explicitly state that OSS/GPU inference is not part of Phase 1.

Do not deploy anything.

After completing the task, show me the resulting directory tree.
```

---

## Task 1.5 — Terraform foundation

**Owner: Cursor**

### Cursor Prompt

```text
Create the Terraform foundation for the GCP Paperclip platform.

Requirements:

Variables:
- project_id
- region
- environment

Enable/configure infrastructure for:

- Cloud Run
- Artifact Registry
- Cloud SQL Admin API
- Secret Manager
- IAM
- Cloud Logging
- Cloud Monitoring

Use modular Terraform.

Do NOT:
- create GPU infrastructure
- create GKE
- create public secrets
- run terraform apply

Create:

infra/terraform/modules/
infra/terraform/environments/dev/

Provide:

terraform init
terraform validate
terraform plan

commands for me to execute manually.

Use sensible variable validation and outputs.
```

### My validation

Run:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan
```

Do not apply until the plan looks correct.

Then:

```bash
terraform apply
```

---

## Task 1.6 — Artifact Registry

**Owner: Cursor**

### Cursor Prompt

```text
Add an Artifact Registry Docker repository to the Terraform configuration.

Repository name:

paperclip-platform

Requirements:

- same primary GCP region as Cloud Run
- Docker format
- repository description
- output the repository URL
- do not make repository publicly writable

Update documentation with the Docker image naming convention:

<REGION>-docker.pkg.dev/<PROJECT_ID>/paperclip-platform/<IMAGE>:<TAG>

Do not run terraform apply.
```

Google recommends Artifact Registry for Cloud Run container deployments.

---

## Task 1.7 — Service accounts

**Owner: Cursor**

### Cursor Prompt

```text
Create least-privilege GCP service accounts using Terraform.

Create:

1. paperclip-runtime
2. litellm-runtime

For Paperclip runtime, prepare permissions needed for:
- Secret Manager access to explicitly assigned secrets
- Cloud SQL connection
- logging

For LiteLLM runtime, prepare permissions needed for:
- explicitly assigned secrets
- logging

Do not assign broad Editor or Owner roles.

Document every IAM role assigned and why it is required.
```

---

## Task 1.8 — Cloud SQL PostgreSQL

**Owner: Cursor**

### Cursor Prompt

```text
Add a Cloud SQL PostgreSQL instance for Paperclip.

This is initially a low-volume personal/dev deployment.

Requirements:

- PostgreSQL
- smallest sensible development configuration
- automated backups enabled
- deletion protection appropriate for dev
- database named paperclip
- application user named paperclip_app
- database password must be stored in Secret Manager
- Paperclip Cloud Run service must connect securely
- database must not expose credentials in Terraform outputs
- avoid public database exposure where practical

Make instance sizing configurable.

Document:
- connection architecture
- database migration procedure
- backup strategy
- upgrade strategy

Do not run terraform apply.
```

Paperclip explicitly documents external PostgreSQL as the intended production architecture.

---

## Task 1.9 — Paperclip container

**Owner: Cursor**

### Cursor Prompt

```text
Inspect the current Paperclip repository and its existing Dockerfile before making changes.

Prepare Paperclip for deployment to Google Cloud Run.

Requirements:

- reuse the upstream Dockerfile when practical rather than creating unnecessary divergence
- listen on Cloud Run's PORT environment variable
- production mode
- external PostgreSQL connection through environment configuration
- health endpoint if already supported
- graceful shutdown
- logs to stdout/stderr
- no credentials baked into the image

Verify the upstream Paperclip build commands rather than assuming them.

Create any wrapper configuration only when needed.

Provide commands to:

1. build locally
2. run locally
3. build with Google Cloud Build
4. push to Artifact Registry

Do not deploy yet.
```

The current Paperclip source lists Node.js 20+ and pnpm 9.15+ as requirements and exposes standard build/test commands.

---

## Task 1.10 — Cloud Run Paperclip service

**Owner: Cursor**

### Cursor Prompt

```text
Create Terraform for the Paperclip Cloud Run service.

Requirements:

Service name:
paperclip

Configuration:
- CPU-only
- no GPU
- low-cost development sizing
- min instances = 0 initially if compatible with Paperclip execution behavior
- bounded max instances
- Cloud SQL connection
- dedicated paperclip-runtime service account
- secrets referenced from Secret Manager
- logs enabled
- health checks where supported
- environment-specific configuration

Do not make the application publicly accessible unless explicitly configured by a variable.

Document how authenticated access works.

Do not run terraform apply.
```

Cloud Run can reference secrets directly from Secret Manager as environment variables or mounted volumes.

---

## Task 1.11 — Validate Paperclip

**Owner: Me**

### Validation

1. Open Cloud Run.
2. Verify `paperclip` is healthy.
3. Open the Paperclip UI.
4. Create a test company/workspace.
5. Create one temporary agent.
6. Create one test task.
7. Restart/redeploy Paperclip.
8. Verify Paperclip state remains in PostgreSQL.
9. Review Cloud Run logs.
10. Verify no database password/API key appears in logs.

### Phase 1 Exit Gate

Do not continue until:

```text
Paperclip reachable       PASS
PostgreSQL connected      PASS
State survives restart    PASS
Secrets protected         PASS
Cloud Run logs clean      PASS
No GPU infrastructure     PASS
```

---

# PHASE 2 — Deploy LLM Gateway

## Goal

Introduce a single inference gateway:

```text
Paperclip
    │
    ▼
Paperclip Adapter
    │
    ▼
LiteLLM
    │
    ├── worker
    ├── reasoning
    └── premium
```

LiteLLM supports a unified OpenAI-style interface across Gemini, Anthropic, Vertex AI and many other providers, along with routing/fallback capabilities.

Gemini itself also exposes OpenAI-compatible APIs, although Google recommends the native Gemini API for new integrations that do not specifically require OpenAI compatibility.

---

## Phase 2 Tasks

| Task | Owner |
|---|---|
| 2.1 Choose provider authentication | Me |
| 2.2 Obtain Gemini credentials | Me |
| 2.3 Obtain Anthropic credential | Me |
| 2.4 Deploy LiteLLM | Cursor |
| 2.5 Configure aliases | Cursor |
| 2.6 Create Paperclip HTTP adapter | Cursor |
| 2.7 Test gateway | Me |

---

## Task 2.1 — Authentication decision

**Owner: Me**

For the production GCP architecture, choose whether Gemini calls will use:

```text
Option A
Gemini API key

Option B
Vertex AI + GCP IAM
```

Recommended longer-term architecture:

```text
Vertex AI + GCP IAM
```

because Paperclip already lives inside GCP.

For the fastest prototype, Gemini API keys are simpler.

---

## Task 2.2 — Gemini credentials

**Owner: Me**

Create the credential appropriate to your selected path.

Do not:

- put it in `.env` committed to Git
- paste it into Terraform
- give it directly to Cursor

Store it manually in Secret Manager.

Example secret name:

```text
gemini-api-key
```

---

## Task 2.3 — Claude credentials

**Owner: Me**

Store:

```text
anthropic-api-key
```

in Secret Manager.

Claude remains the premium fallback, not the default model.

---

## Task 2.4 — Deploy LiteLLM

**Owner: Cursor**

### Cursor Prompt

```text
Add LiteLLM Proxy as the central LLM gateway.

Architecture:

Paperclip adapter
      ->
LiteLLM Cloud Run service
      ->
Gemini / Anthropic

Requirements:

- Cloud Run
- CPU only
- min instances 0 if operationally suitable
- dedicated litellm-runtime service account
- provider secrets obtained from Secret Manager
- structured logging
- health endpoint
- no provider keys visible to Paperclip agents
- gateway authentication required
- no anonymous public API

Create:

gateway/
  Dockerfile
  config/
  README.md

Use the current supported LiteLLM configuration syntax based on the installed version. Do not invent deprecated configuration fields.

Do not run terraform apply.
```

---

## Task 2.5 — Model aliases

**Owner: Cursor**

### Cursor Prompt

```text
Configure three logical model aliases in LiteLLM.

Aliases:

worker
reasoning
premium

Initial intent:

worker
  -> inexpensive Gemini Flash-class model

reasoning
  -> stronger Gemini reasoning/Pro-class model

premium
  -> Claude

Important:

- inspect current Google and Anthropic model IDs before hard-coding them
- keep actual provider model IDs configurable
- Paperclip agents should refer to aliases rather than provider model IDs
- define maximum output-token defaults
- configure safe provider timeout values
- configure limited retry behavior
- do not automatically escalate between aliases yet

Document how I can change the underlying provider model without modifying Paperclip agents.
```

---

## Task 2.6 — Paperclip gateway adapter

**Owner: Cursor**

### Cursor Prompt

```text
Implement a Paperclip agent adapter that calls the LiteLLM HTTP gateway.

Before implementation:

1. Inspect Paperclip's current adapter architecture.
2. Read the repository's create-agent-adapter guidance.
3. Examine existing adapters for conventions.
4. Verify whether the installed Paperclip version already contains a generic HTTP/OpenAI-compatible adapter that meets the requirement.

If a suitable built-in adapter already exists:
- configure and reuse it
- do not build duplicate functionality

If it does not exist:
- create a dedicated adapter under Paperclip's supported adapter structure

Adapter requirements:

- call the LiteLLM OpenAI-compatible endpoint
- model alias configurable per agent
- session/task context passed correctly
- timeout handling
- HTTP error handling
- usage metadata captured where available
- request ID captured
- no provider credentials embedded
- gateway authentication comes from Secret Manager/environment
- unit tests
- minimal changes to Paperclip core

Name custom implementation something clear such as:

litellm-http

Do not modify unrelated Paperclip functionality.

Provide:
- files changed
- adapter registration steps
- configuration example
- tests
- upgrade considerations
```

Paperclip's current adapter documentation explicitly describes adapters for CLI runtimes, custom processes and HTTP endpoints, making this the clean extension point.

---

## Task 2.7 — Gateway validation

**Owner: Me**

Test:

```text
worker     → simple summary
reasoning  → architecture question
premium    → one controlled Claude request
```

Confirm in LiteLLM logs:

```text
Correct alias
Correct provider
Token counts
Latency
HTTP success
```

### Phase 2 Exit Gate

```text
Paperclip → LiteLLM             PASS
worker → Gemini                 PASS
reasoning → Gemini              PASS
premium → Claude                PASS
Claude not default              PASS
No credentials exposed          PASS
```

---

# PHASE 3 — Agent-Specific Routing

## Goal

Assign the cheapest acceptable model to each job.

Example:

| Agent | Default |
|---|---|
| News collector | worker |
| Extractor | worker |
| Summarizer | worker |
| Research agent | worker |
| Blog writer | worker |
| Planner | reasoning |
| Architect | reasoning |
| Developer | Codex |
| Premium reviewer | premium |

---

## Task 3.1 — Define agent roster

**Owner: Me**

Create a simple spreadsheet or Markdown table containing:

```text
Agent
Purpose
Expected frequency
Task complexity
Default model
Fallback model
Max iterations
```

Do not start by creating twenty agents.

Start with approximately 3–5 important agents.

---

## Task 3.2 — Implement model configuration

**Owner: Cursor**

### Cursor Prompt

```text
Create an agent model-policy configuration layer.

Each Paperclip agent must be able to specify:

agent_id
model_alias
fallback_alias
max_output_tokens
max_iterations
max_tool_calls
timeout
allow_escalation

Use logical aliases:

worker
reasoning
premium

Keep this configuration outside core Paperclip logic where practical.

Add schema validation and documentation.

Do not implement automatic LLM-based complexity classification.
```

---

## Task 3.3 — Configure first agents

**Owner: Me**

For the initial system, configure something like:

```text
Research Agent
worker → reasoning

Content Agent
worker → reasoning

Developer Agent
Codex

Planner
reasoning → premium
```

Manually run 10–20 representative tasks.

Record:

```text
Task
Model
Success
Quality
Escalation needed?
```

---

# PHASE 4 — Deterministic Escalation

## Goal

Avoid jumping straight to Claude.

```text
worker
  │
  ├── PASS → done
  │
  └── FAIL
       ↓
reasoning
  │
  ├── PASS → done
  │
  └── FAIL
       ↓
premium
```

---

## Task 4.1 — Define escalation policy

**Owner: Me**

Approve escalation when:

```text
schema validation fails
required tool execution fails
tests fail
output explicitly declares NEED_ESCALATION
response empty
task marked critical
maximum worker attempts reached
```

Initially configure:

```text
worker retries       = 1
reasoning retries    = 1
premium retries      = 0–1
```

Avoid unlimited retry loops.

---

## Task 4.2 — Implement escalation engine

**Owner: Cursor**

### Cursor Prompt

```text
Implement deterministic model escalation.

Allowed chain:

worker
  -> reasoning
  -> premium

Escalation triggers:

- output validation failure
- structured output/schema validation failure
- required tool execution failure
- explicit NEED_ESCALATION result
- designated critical task
- configured retry exhaustion

Requirements:

- never downgrade and retry indefinitely
- maximum escalation depth = 2
- configurable per agent
- log each transition
- preserve task ID
- preserve agent ID
- preserve correlation ID
- record original model
- record final model
- unit tests for success/failure paths

Do NOT add an extra LLM request solely to decide whether escalation is needed.
```

---

## Task 4.3 — Failure testing

**Owner: Me**

Test deliberately:

1. Force invalid JSON.
2. Force a tool failure.
3. Cause an impossible worker task.
4. Verify worker → reasoning.
5. Cause reasoning failure.
6. Verify reasoning → premium.
7. Confirm execution stops after premium.
8. Confirm no infinite loop.

### Phase 4 Exit Gate

```text
Normal task remains worker        PASS
Worker failure escalates          PASS
Reasoning failure escalates       PASS
Retry limit enforced              PASS
Claude usage controlled           PASS
Infinite loops impossible         PASS
```

---

# PHASE 5 — Cost Observability

## Goal

Know exactly:

> **What did this agent task cost me?**

Architecture:

```text
Paperclip
    │
LiteLLM
    │
    ├── Provider
    │
    └── Usage Event
           │
           ▼
       BigQuery
           │
           ▼
       Dashboard
```

---

## Task 5.1 — Define KPIs

**Owner: Me**

Use these initial KPIs:

```text
Cost / agent
Cost / task
Cost / successful task
Input tokens
Output tokens
Requests
Retries
Escalations
Claude escalation %
Failure %
Latency
```

Primary KPI:

```text
Cost per successfully completed task
```

---

## Task 5.2 — Usage instrumentation

**Owner: Cursor**

### Cursor Prompt

```text
Implement structured LLM usage telemetry.

For every inference request capture:

timestamp
environment
agent_id
task_id
workflow_id if available
correlation_id
model_alias
provider
provider_model
input_tokens
output_tokens
estimated_cost
latency_ms
success
error_type
retry_number
escalated
previous_model_alias
final_model_alias

Requirements:

- never log prompts containing secrets by default
- never log API credentials
- use structured JSON logs
- make telemetry asynchronous where practical
- logging failure must not fail an agent task
```

---

## Task 5.3 — BigQuery sink

**Owner: Cursor**

### Cursor Prompt

```text
Create Terraform and implementation for LLM cost analytics in BigQuery.

Create a dataset suitable for:

paperclip_cost

Create the required usage table/schema.

Implement an ingestion mechanism from structured gateway logs.

Optimize initially for simplicity and low cost.

Provide queries for:

1. spend by agent
2. spend by model
3. spend by day
4. cost per successful task
5. escalation percentage
6. Claude spend
7. top 10 expensive tasks
8. input/output token ratios

Do not create an unnecessarily complex data pipeline.
```

---

## Task 5.4 — Dashboard

**Owner: Cursor**

### Cursor Prompt

```text
Create the simplest practical cost dashboard using the telemetry we have implemented.

Dashboard must show:

Total LLM spend
Spend today
Spend this month
Spend by agent
Spend by provider/model
Cost per successful task
Claude percentage
Escalation percentage
Failure percentage
Top expensive agents

Prefer native Google Cloud / BigQuery-compatible visualization unless another existing project tool is already present.

Document how to access and interpret the dashboard.
```

---

## Task 5.5 — My weekly review

**Owner: Me**

Review:

```text
Most expensive agent
Most expensive workflow
Claude %
Escalation %
Failed tasks
Large-context agents
Excessive retries
```

Target:

```text
Claude execution share < 5–10%
```

unless measured quality demonstrates that more premium usage is justified.

---

# PHASE 6 — Optimize Agent Execution

## Goal

Reduce calls before trying to reduce model price.

Paperclip supports scheduled heartbeats as well as event-based triggers, so unnecessary polling should be minimized.

---

## Task 6.1 — Heartbeat analysis

**Owner: Me**

For every agent ask:

```text
Does this agent need to wake periodically?

Can it run only when:
- task assigned
- mention received
- event occurs
- scheduled work is actually due?
```

Disable frequent heartbeats on inactive agents.

---

## Task 6.2 — Execution guardrails

**Owner: Cursor**

### Cursor Prompt

```text
Add execution-cost guardrails to Paperclip agent configuration.

Support:

max_iterations
max_tool_calls
max_output_tokens
max_runtime_seconds
max_escalations
optional per-task estimated-cost ceiling

When a limit is reached:

- stop gracefully
- record reason
- mark the task for review where appropriate
- do not silently continue using a more expensive model

Add tests for every guardrail.
```

---

## Task 6.3 — Context optimization

**Owner: Cursor**

### Cursor Prompt

```text
Analyze how agent context is currently assembled.

Identify opportunities to reduce repeated context tokens.

Implement only low-risk optimizations such as:

- send current task instead of entire unrelated task history
- retrieve relevant context on demand
- summarize stale conversation state
- avoid duplicating system instructions
- cache stable instructions
- avoid repeatedly sending unchanged documents

Before changing behavior, document current context construction.

After implementation, measure representative prompt token reduction.

Do not sacrifice required task context solely to reduce tokens.
```

---

# PHASE 7 — OSS Model Evaluation

## Do not start this phase until Phase 5 has produced real usage data.

## Goal

Determine whether:

```text
Gemini API cost
      >
OSS inference infrastructure cost
```

for a specific high-volume workload.

---

## Task 7.1 — Identify candidates

**Owner: Me**

Look for tasks that are:

```text
high volume
simple
repeatable
latency tolerant
not requiring frontier reasoning
```

Examples:

```text
classification
metadata generation
summarization
structured extraction
simple transformation
```

---

## Task 7.2 — Benchmark harness

**Owner: Cursor**

### Cursor Prompt

```text
Create an LLM benchmark harness for evaluating whether an OSS model should replace the current worker model.

The benchmark must run the same representative task dataset against:

1. current worker Gemini model
2. future OpenAI-compatible OSS endpoint

Measure:

success rate
structured-output validity
latency
input/output tokens
estimated API cost
tokens/sec where available
human evaluation placeholder
task-level pass/fail

Store benchmark definitions separately from model implementations.

Do not deploy GPUs yet.
```

---

## Task 7.3 — Select OSS models

**Owner: Me**

Pick 2–3 candidates based upon actual workload requirements.

Do not choose models purely because they are popular.

Evaluate:

```text
model quality
VRAM requirement
context requirement
tool calling
structured outputs
throughput
license
```

---

## Task 7.4 — Temporary Cloud Run GPU

**Owner: Cursor**

Only after I explicitly approve GPU testing, use:

### Cursor Prompt

```text
Create a TEMPORARY Cloud Run GPU benchmark environment.

Important:
This is benchmark infrastructure, not production.

Requirements:

- vLLM
- one selected OSS model
- OpenAI-compatible endpoint
- min instances = 0
- strict max instances
- clear resource labels identifying benchmark/test
- easy terraform destroy path
- detailed GPU runtime cost monitoring
- no production routing yet

The OSS endpoint must sit behind the existing LiteLLM abstraction.

Do not modify production routing.

Provide:

terraform plan
deployment commands
benchmark commands
cleanup commands

Do not run terraform apply automatically.
```

---

## Task 7.5 — Benchmark

**Owner: Me + Cursor**

Cursor runs technical benchmarks.

I evaluate output quality.

Compare:

```text
Gemini worker
vs
OSS worker
```

on:

```text
$/task
quality
latency
failure rate
operations overhead
GPU utilization
```

---

# PHASE 8 — OSS Production Decision

## Owner: Me

Move OSS into production only if:

```text
OSS cost advantage is meaningful
AND
quality is acceptable
AND
workload volume is sustained
AND
operational overhead is acceptable
```

Do not deploy OSS merely because:

```text
"open source should be cheaper."
```

If approved, production evolves into:

```text
                            Paperclip
                                │
                                ▼
                            Adapter
                                │
                                ▼
                            LiteLLM
                                │
          ┌─────────────────────┼─────────────────────┐
          │                     │                     │
          ▼                     ▼                     ▼
      OSS Worker          Gemini Worker         Gemini Reasoning
     high volume             fallback                 │
          │                                            ▼
      vLLM/GPU                                      Claude
                                                  premium only
```

---

# Final Deployment Sequence

Execute in exactly this order:

```text
PHASE 1
Paperclip
Cloud Run
Cloud SQL
Artifact Registry
        │
        ▼
PHASE 2
LiteLLM
Gemini
Claude
Paperclip Adapter
        │
        ▼
PHASE 3
Agent model policies
        │
        ▼
PHASE 4
Deterministic escalation
        │
        ▼
PHASE 5
Cost observability
        │
        ▼
PHASE 6
Execution optimization
        │
        ▼
COLLECT REAL DATA
        │
        ▼
PHASE 7
OSS benchmark
        │
        ▼
PHASE 8
Go / No-Go
        │
        ├── NO → remain API-first
        │
        └── YES
               ↓
          vLLM + GPU
          for selected
          high-volume tasks
```

# Recommended First Implementation Milestone

Do **not** ask Cursor to implement all eight phases immediately.

The first milestone should end here:

```text
Paperclip
   ↓
Cloud Run
   ↓
Cloud SQL

+

Paperclip
   ↓
LiteLLM
   ↓
Gemini worker
```

Once that works reliably, add:

```text
reasoning
premium
routing
escalation
observability
```

This keeps debugging simple and prevents architecture complexity from hiding basic deployment problems.

# Definition of Done — Initial Platform

The initial platform is complete when:

```text
[PASS] Paperclip runs on Cloud Run
[PASS] Paperclip state persists in PostgreSQL
[PASS] Gemini worker model works
[PASS] Gemini reasoning model works
[PASS] Claude premium model works
[PASS] Paperclip agents use logical model aliases
[PASS] Worker is the default
[PASS] Claude is escalation only
[PASS] Retry loops are bounded
[PASS] Cost is attributed to agents/tasks
[PASS] Secrets are stored in Secret Manager
[PASS] No GPU is running
[PASS] OSS benchmark is deferred until supported by real usage data
```