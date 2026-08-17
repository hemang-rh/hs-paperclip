# GCP bootstrap (Phase 0)

`scripts/bootstrap-gcp.sh` is the one-time, manually-run script that creates
everything Terraform itself needs before it can run. It is idempotent (safe to
re-run) and **never creates service-account JSON keys**.

The GCP project and billing account are **not** created here. Create the
project, link billing, and pick a region first, then run this script.

## Prerequisites

- `gcloud` on `PATH`, authenticated (`gcloud auth login`)
- Permission to enable APIs, create buckets, create service accounts, and set
  IAM on the target project (typically Project Owner or equivalent for this
  one-time step)
- A unique GCS bucket name for Terraform state

## Usage

Flags override environment. All four inputs are required and validated up front.

```bash
gcloud auth login
gcloud auth application-default login

./scripts/bootstrap-gcp.sh \
  --project-id PROJECT_ID \
  --region us-central1 \
  --github-repo OWNER/REPO \
  --state-bucket PROJECT_ID-tf-state
```

Environment equivalents: `PROJECT_ID` / `GCP_PROJECT_ID`, `REGION` /
`GCP_REGION`, `GITHUB_REPO`, `STATE_BUCKET` / `TF_STATE_BUCKET`.

Optional overrides (rarely needed): `WIF_POOL_ID` (default `github-actions`),
`WIF_PROVIDER_ID` (default `github-oidc`), `SA_ID` (default `terraform-deployer`).

Do not pass `--project` to `gcloud config set` unless you want to change your
local default; the script passes `--project` on every call.

## What it creates

| Resource | ID / name | Notes |
|---|---|---|
| Enabled APIs | see list below | Skips APIs already enabled |
| GCS bucket | `gs://$STATE_BUCKET` | Terraform remote state. Versioning on, uniform bucket-level access, public access prevention enforced. Created in `$REGION`. |
| WIF pool | `github-actions` | Global. Soft-deleted pools with the same ID are undeleted on re-run. |
| OIDC provider | `github-oidc` | Issuer `https://token.actions.githubusercontent.com`. Attribute condition pins `assertion.repository` to **this** GitHub repo. |
| Service account | `terraform-deployer@$PROJECT_ID.iam.gserviceaccount.com` | No keys. Bound to the WIF provider via `roles/iam.workloadIdentityUser` scoped to `attribute.repository/$GITHUB_REPO`. |

On re-run the script re-asserts bucket hardening and the OIDC attribute
condition, so a previously unconstrained provider is tightened.

### APIs

- `run.googleapis.com`
- `sqladmin.googleapis.com`
- `artifactregistry.googleapis.com`
- `secretmanager.googleapis.com`
- `compute.googleapis.com`
- `servicenetworking.googleapis.com`
- `iam.googleapis.com`
- `iamcredentials.googleapis.com`
- `sts.googleapis.com` (token exchange for WIF; required for GitHub Actions)
- `cloudresourcemanager.googleapis.com`
- `storage.googleapis.com`
- `certificatemanager.googleapis.com`
- `logging.googleapis.com`
- `monitoring.googleapis.com`

### `terraform-deployer` project roles

Specific and minimal for the Terraform modules this repo will apply — not
`roles/owner`, not `roles/editor`, and not `roles/iam.serviceAccountKeyAdmin`
(that role would let CI mint JSON keys).

| Role | Why |
|---|---|
| `roles/compute.networkAdmin` | VPC, `/26` subnet, PSA allocated range, firewall |
| `roles/compute.loadBalancerAdmin` | Global ALB, serverless NEG, forwarding rules |
| `roles/compute.securityAdmin` | Cloud Armor policies |
| `roles/servicenetworking.networksAdmin` | Private Service Access peering |
| `roles/cloudsql.admin` | Cloud SQL PostgreSQL instance, database, user |
| `roles/artifactregistry.admin` | Artifact Registry repo and CI image push |
| `roles/secretmanager.admin` | Secret containers, replication, per-secret IAM (not values) |
| `roles/storage.admin` | Uploads bucket, HMAC keys, and the state bucket |
| `roles/run.admin` | Cloud Run services and jobs |
| `roles/iam.serviceAccountAdmin` | Runtime and HMAC service accounts |
| `roles/iam.serviceAccountUser` | `actAs` those SAs when deploying Cloud Run |
| `roles/resourcemanager.projectIamAdmin` | Bind `logging.logWriter` / `cloudtrace.agent` onto runtime SAs. Broadest role in this set. |
| `roles/certificatemanager.owner` | Google-managed certificates and maps |
| `roles/logging.configWriter` | Log-based metrics |
| `roles/monitoring.editor` | Alerting policies and notification channels |

`projectIamAdmin` can grant any project role, including ones this SA should not
have. That is the trade-off for letting Terraform manage runtime IAM in-band.
Do not add `roles/iam.serviceAccountKeyAdmin`.

### Workload Identity Federation (do not broaden)

GitHub's OIDC issuer is shared by **every** GitHub repository. A provider with
no attribute condition is a privilege-escalation footgun: any repo could mint a
token that enters the pool, and a sloppy IAM binding (`*` or
`repository_owner` only) would then impersonate `terraform-deployer`.

This bootstrap pins trust twice:

1. Provider attribute condition: `assertion.repository == 'OWNER/REPO'`
2. SA binding: `principalSet://.../attribute.repository/OWNER/REPO` with
   `roles/iam.workloadIdentityUser`

Do not remove the condition. Do not replace the member with
`principalSet://.../*` or an org-wide `repository_owner` principal.

## GitHub repository variables

The script prints these at the end. Add them under **Settings → Secrets and
variables → Actions → Variables**. They are not secrets.

| Variable | Value |
|---|---|
| `GCP_WIF_PROVIDER` | Full provider resource name (`projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github-oidc`) |
| `GCP_DEPLOYER_SA` | `terraform-deployer@PROJECT_ID.iam.gserviceaccount.com` |
| `GCP_PROJECT_ID` | Project ID |
| `GCP_REGION` | Region passed to the script |
| `TF_STATE_BUCKET` | State bucket name |

Also create a GitHub Environment named `prod` with required reviewers. The
Terraform apply workflow gates on it.

Copy-paste via `gh` (from the repo checkout):

```bash
gh variable set GCP_WIF_PROVIDER --body "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github-oidc"
gh variable set GCP_DEPLOYER_SA  --body "terraform-deployer@PROJECT_ID.iam.gserviceaccount.com"
gh variable set GCP_PROJECT_ID   --body "PROJECT_ID"
gh variable set GCP_REGION       --body "us-central1"
gh variable set TF_STATE_BUCKET  --body "PROJECT_ID-tf-state"
```

Use the exact strings the script printed; `GCP_WIF_PROVIDER` must use the
**project number**, not the project ID.

## What this script does not create

- The GCP project or billing link
- DNS zones or registrar records
- Service-account JSON keys
- Anything Terraform manages (VPC, Cloud SQL, Cloud Run, secrets **values**,
  uploads bucket, load balancer)

Secret **values** are seeded later with `scripts/seed-secrets.sh`, not here.

## Teardown

Destroy Terraform-managed infrastructure **first** (`terraform destroy` in
`infra/terraform/envs/prod`, after you have accepted that it will delete Cloud
SQL, the uploads bucket, and Cloud Run). Then remove bootstrap resources.

Deleting the state bucket while live infrastructure still exists leaves you
with no inventory of what is running. Do that last, and only on purpose.

Substitute the same values you passed to the script.

```bash
PROJECT_ID="PROJECT_ID"
PROJECT_NUMBER="PROJECT_NUMBER"
REGION="us-central1"
GITHUB_REPO="OWNER/REPO"
STATE_BUCKET="PROJECT_ID-tf-state"
WIF_POOL_ID="github-actions"
WIF_PROVIDER_ID="github-oidc"
SA_EMAIL="terraform-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GITHUB_REPO}"

# 1. GitHub: delete the five repository variables and the `prod` environment.

# 2. WIF binding on the deployer SA
gcloud iam service-accounts remove-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="${WIF_MEMBER}"

# 3. OIDC provider, then pool (provider must go first)
gcloud iam workload-identity-pools providers delete "${WIF_PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location=global \
  --workload-identity-pool="${WIF_POOL_ID}"
gcloud iam workload-identity-pools delete "${WIF_POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location=global

# 4. Project roles (repeat for each role listed in the table above)
for role in \
  roles/compute.networkAdmin \
  roles/compute.loadBalancerAdmin \
  roles/compute.securityAdmin \
  roles/servicenetworking.networksAdmin \
  roles/cloudsql.admin \
  roles/artifactregistry.admin \
  roles/secretmanager.admin \
  roles/storage.admin \
  roles/run.admin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/resourcemanager.projectIamAdmin \
  roles/certificatemanager.owner \
  roles/logging.configWriter \
  roles/monitoring.editor
do
  gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --quiet || true
done

# 5. Service account (this does not mint or download a key)
gcloud iam service-accounts delete "${SA_EMAIL}" --project="${PROJECT_ID}"

# 6. State bucket — DESTRUCTIVE. Versioning means you must purge generations.
gcloud storage rm -r "gs://${STATE_BUCKET}"
```

WIF pools and providers are soft-deleted for about 30 days. Re-running the
bootstrap script undeletes them if you recreate with the same IDs.

Leave the APIs enabled unless you are abandoning the project; disabling them
breaks any remaining resources. To disable the project entirely, delete the
project in the console instead of picking APIs apart.
