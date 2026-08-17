#!/usr/bin/env bash
# One-time GCP bootstrap for Terraform + GitHub Actions.
#
# Creates the project-level prerequisites Terraform cannot create for itself:
# APIs, the state bucket, a GitHub-constrained Workload Identity Federation
# provider, and a least-privilege terraform-deployer service account.
#
# Idempotent: safe to re-run. Re-running re-asserts bucket hardening, the WIF
# attribute condition, IAM roles, and the workloadIdentityUser binding.
#
# This script must never create service-account JSON keys
# (no `gcloud iam service-accounts keys create`).
set -euo pipefail

# ---------------------------------------------------------------------------
# Logging / usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-gcp.sh [options]

One-time, manually-run bootstrap. Creates everything Terraform needs before it
can run. Idempotent. Never creates service-account JSON keys.

Options (flags override environment):
  --project-id    PROJECT_ID     GCP project ID
  --region        REGION         Region for the state bucket (e.g. us-central1)
  --github-repo   GITHUB_REPO    GitHub repository as owner/name
  --state-bucket  STATE_BUCKET   GCS bucket name for Terraform state (no gs://)

Environment (used if the corresponding flag is omitted):
  PROJECT_ID or GCP_PROJECT_ID
  REGION     or GCP_REGION
  GITHUB_REPO
  STATE_BUCKET or TF_STATE_BUCKET

Optional overrides:
  WIF_POOL_ID       Workload Identity pool ID       (default: github-actions)
  WIF_PROVIDER_ID   OIDC provider ID                (default: github-oidc)
  SA_ID             Deployer service account ID     (default: terraform-deployer)

Examples:
  scripts/bootstrap-gcp.sh \
    --project-id my-project \
    --region us-central1 \
    --github-repo my-org/hs-paperclip \
    --state-bucket my-project-tf-state

  PROJECT_ID=my-project REGION=us-central1 \
    GITHUB_REPO=my-org/hs-paperclip STATE_BUCKET=my-project-tf-state \
    scripts/bootstrap-gcp.sh
EOF
}

log()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Defaults from the environment (flags override below)
# ---------------------------------------------------------------------------

PROJECT_ID="${PROJECT_ID:-${GCP_PROJECT_ID:-}}"
REGION="${REGION:-${GCP_REGION:-}}"
GITHUB_REPO="${GITHUB_REPO:-}"
STATE_BUCKET="${STATE_BUCKET:-${TF_STATE_BUCKET:-}}"

WIF_POOL_ID="${WIF_POOL_ID:-github-actions}"
WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-github-oidc}"
SA_ID="${SA_ID:-terraform-deployer}"

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --project-id|--project)
      [[ $# -ge 2 ]] || die "missing value for $1"
      PROJECT_ID="$2"
      shift 2
      ;;
    --project-id=*|--project=*)
      PROJECT_ID="${1#*=}"
      shift
      ;;
    --region)
      [[ $# -ge 2 ]] || die "missing value for $1"
      REGION="$2"
      shift 2
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --github-repo)
      [[ $# -ge 2 ]] || die "missing value for $1"
      GITHUB_REPO="$2"
      shift 2
      ;;
    --github-repo=*)
      GITHUB_REPO="${1#*=}"
      shift
      ;;
    --state-bucket)
      [[ $# -ge 2 ]] || die "missing value for $1"
      STATE_BUCKET="$2"
      shift 2
      ;;
    --state-bucket=*)
      STATE_BUCKET="${1#*=}"
      shift
      ;;
    *)
      die "unknown argument: $1 (see --help)"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

missing=()
[[ -n "${PROJECT_ID}"   ]] || missing+=("PROJECT_ID (--project-id)")
[[ -n "${REGION}"       ]] || missing+=("REGION (--region)")
[[ -n "${GITHUB_REPO}"  ]] || missing+=("GITHUB_REPO (--github-repo)")
[[ -n "${STATE_BUCKET}" ]] || missing+=("STATE_BUCKET (--state-bucket)")
if [[ ${#missing[@]} -gt 0 ]]; then
  die "missing required inputs: ${missing[*]}"
fi

# Accept a gs:// prefix if the operator pasted a URI.
STATE_BUCKET="${STATE_BUCKET#gs://}"
STATE_BUCKET="${STATE_BUCKET%%/*}"

[[ "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] \
  || die "PROJECT_ID '${PROJECT_ID}' is not a valid GCP project ID (6-30 chars, lowercase letter, digit, hyphen; must start with a letter and not end with a hyphen)"

[[ "${REGION}" =~ ^[a-z]+-[a-z]+[0-9]+$ ]] \
  || die "REGION '${REGION}' is not a valid GCP region (expected e.g. us-central1)"

[[ "${GITHUB_REPO}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] \
  || die "GITHUB_REPO '${GITHUB_REPO}' must be owner/name (exactly one slash)"

[[ "${STATE_BUCKET}" =~ ^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$ ]] \
  || die "STATE_BUCKET '${STATE_BUCKET}' is not a valid GCS bucket name (3-63 chars, lowercase, digits, dots, hyphens, underscores)"

[[ "${WIF_POOL_ID}" =~ ^[a-z][a-z0-9-]{2,30}[a-z0-9]$ ]] \
  || die "WIF_POOL_ID '${WIF_POOL_ID}' is not a valid pool ID (4-32 chars, [a-z0-9-])"
[[ "${WIF_POOL_ID}" == gcp-* ]] \
  && die "WIF_POOL_ID '${WIF_POOL_ID}' must not use the reserved gcp- prefix"
[[ "${WIF_PROVIDER_ID}" =~ ^[a-z][a-z0-9-]{2,30}[a-z0-9]$ ]] \
  || die "WIF_PROVIDER_ID '${WIF_PROVIDER_ID}' is not a valid provider ID (4-32 chars, [a-z0-9-])"
[[ "${SA_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] \
  || die "SA_ID '${SA_ID}' is not a valid service account ID"

command -v gcloud >/dev/null 2>&1 \
  || die "gcloud is not installed or not on PATH"

gcloud auth print-access-token >/dev/null 2>&1 \
  || die "gcloud is not authenticated; run: gcloud auth login && gcloud auth application-default login"

# Never mutate the operator's default gcloud project; pass --project everywhere.
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

log "Validating project ${PROJECT_ID}"
gcloud projects describe "${PROJECT_ID}" >/dev/null \
  || die "project '${PROJECT_ID}' not found or you lack resourcemanager.projects.get"

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
ATTRIBUTE_CONDITION="assertion.repository == '${GITHUB_REPO}'"
ATTRIBUTE_MAPPING="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner"
WIF_MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GITHUB_REPO}"

info "project number: ${PROJECT_NUMBER}"
info "region:         ${REGION}"
info "github repo:    ${GITHUB_REPO}"
info "state bucket:   gs://${STATE_BUCKET}"
info "deployer SA:    ${SA_EMAIL}"

# APIs Terraform (and this WIF setup) need. sts is not in the Terraform-facing
# list; it is required for GitHub Actions to exchange an OIDC token.
APIS=(
  run.googleapis.com
  sqladmin.googleapis.com
  artifactregistry.googleapis.com
  secretmanager.googleapis.com
  compute.googleapis.com
  servicenetworking.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  sts.googleapis.com
  cloudresourcemanager.googleapis.com
  storage.googleapis.com
  certificatemanager.googleapis.com
  logging.googleapis.com
  monitoring.googleapis.com
)

# Least-privilege project roles for terraform-deployer. Not Owner, not Editor,
# and not iam.serviceAccountKeyAdmin (that would let CI mint JSON keys).
# projectIamAdmin is the broadest of these: Terraform must attach
# logging.logWriter / cloudtrace.agent to runtime service accounts it creates.
DEPLOYER_ROLES=(
  roles/compute.networkAdmin                 # VPC, subnet, PSA address, firewall
  roles/compute.loadBalancerAdmin            # ALB, serverless NEG, forwarding
  roles/compute.securityAdmin                # Cloud Armor policies
  roles/servicenetworking.networksAdmin      # Private Service Access peering
  roles/cloudsql.admin                       # Cloud SQL PG instance, user, db
  roles/artifactregistry.admin               # AR repo + CI image push
  roles/secretmanager.admin                  # secret containers + per-secret IAM
  roles/storage.admin                        # uploads bucket, HMAC keys, state
  roles/run.admin                            # Cloud Run services and jobs
  roles/iam.serviceAccountAdmin              # runtime / HMAC service accounts
  roles/iam.serviceAccountUser               # actAs those SAs on Cloud Run
  roles/resourcemanager.projectIamAdmin      # bind project roles onto runtime SAs
  roles/certificatemanager.owner             # Google-managed certs / cert maps
  roles/logging.configWriter                 # log-based metrics
  roles/monitoring.editor                    # alerting policies, channels
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ENABLED_APIS=""

api_enabled() {
  local api="$1"
  grep -Fxq "${api}" <<< "${ENABLED_APIS}"
}

bucket_exists() {
  gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1
}

wif_pool_exists() {
  gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" \
    --project="${PROJECT_ID}" \
    --location=global >/dev/null 2>&1
}

wif_provider_exists() {
  gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location=global \
    --workload-identity-pool="${WIF_POOL_ID}" >/dev/null 2>&1
}

sa_exists() {
  gcloud iam service-accounts describe "${SA_EMAIL}" \
    --project="${PROJECT_ID}" >/dev/null 2>&1
}

project_has_role() {
  local role="$1"
  local members
  members="$(gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten='bindings[].members' \
    --filter="bindings.role='${role}' AND bindings.members='serviceAccount:${SA_EMAIL}'" \
    --format='value(bindings.members)' 2>/dev/null || true)"
  [[ -n "${members}" ]]
}

sa_has_wif_binding() {
  local members
  members="$(gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" \
    --project="${PROJECT_ID}" \
    --flatten='bindings[].members' \
    --filter="bindings.role='roles/iam.workloadIdentityUser' AND bindings.members='${WIF_MEMBER}'" \
    --format='value(bindings.members)' 2>/dev/null || true)"
  [[ -n "${members}" ]]
}

grant_project_role() {
  local role="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="${role}" \
      --condition=None \
      --quiet >/dev/null; then
      return 0
    fi
    info "IAM write conflict on ${role}; retry ${attempt}/5"
    sleep $((attempt * 2))
  done
  die "failed to grant ${role} to ${SA_EMAIL}"
}

# ---------------------------------------------------------------------------
# 1. Enable APIs
# ---------------------------------------------------------------------------

log "Enabling APIs"
ENABLED_APIS="$(gcloud services list --enabled --project="${PROJECT_ID}" --format='value(config.name)')"
to_enable=()
for api in "${APIS[@]}"; do
  if api_enabled "${api}"; then
    info "already enabled: ${api}"
  else
    info "will enable:     ${api}"
    to_enable+=("${api}")
  fi
done
if [[ ${#to_enable[@]} -gt 0 ]]; then
  gcloud services enable "${to_enable[@]}" --project="${PROJECT_ID}"
  log "APIs enabled"
else
  log "All required APIs already enabled"
fi

# ---------------------------------------------------------------------------
# 2. Terraform state bucket
# ---------------------------------------------------------------------------

log "Ensuring Terraform state bucket gs://${STATE_BUCKET}"
if bucket_exists; then
  bucket_project_number="$(gcloud storage buckets describe "gs://${STATE_BUCKET}" \
    --format='value(projectNumber)')"
  if [[ -n "${bucket_project_number}" && "${bucket_project_number}" != "${PROJECT_NUMBER}" ]]; then
    die "gs://${STATE_BUCKET} exists but belongs to project number ${bucket_project_number}, not ${PROJECT_NUMBER}"
  fi
  info "bucket already exists; re-asserting hardening"
else
  info "creating bucket in ${REGION}"
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

info "versioning ON, uniform bucket-level access, public access prevention enforced"
gcloud storage buckets update "gs://${STATE_BUCKET}" \
  --versioning \
  --uniform-bucket-level-access \
  --public-access-prevention

# ---------------------------------------------------------------------------
# 3. Workload Identity Federation (GitHub Actions, this repo only)
# ---------------------------------------------------------------------------

log "Ensuring Workload Identity pool ${WIF_POOL_ID}"
if wif_pool_exists; then
  info "pool already exists"
else
  # Soft-deleted pools occupy the ID for ~30 days; restore rather than fail.
  if gcloud iam workload-identity-pools undelete "${WIF_POOL_ID}" \
      --project="${PROJECT_ID}" \
      --location=global >/dev/null 2>&1; then
    info "restored soft-deleted pool ${WIF_POOL_ID}"
  else
    info "creating pool"
    gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
      --project="${PROJECT_ID}" \
      --location=global \
      --display-name="GitHub Actions" \
      --description="WIF pool for GitHub Actions in ${GITHUB_REPO} only. Do not broaden."
  fi
fi

log "Ensuring GitHub OIDC provider ${WIF_PROVIDER_ID} (constrained to ${GITHUB_REPO})"
# A provider with no attribute condition trusts every GitHub repo that can mint
# an OIDC token. Constrain admission to this repository, then also scope the
# SA binding below to attribute.repository/${GITHUB_REPO}.
if wif_provider_exists; then
  info "provider already exists; re-asserting attribute condition"
  gcloud iam workload-identity-pools providers update-oidc "${WIF_PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location=global \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="${ATTRIBUTE_MAPPING}" \
    --attribute-condition="${ATTRIBUTE_CONDITION}"
else
  if gcloud iam workload-identity-pools providers undelete "${WIF_PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location=global \
      --workload-identity-pool="${WIF_POOL_ID}" >/dev/null 2>&1; then
    info "restored soft-deleted provider ${WIF_PROVIDER_ID}; re-asserting attribute condition"
    gcloud iam workload-identity-pools providers update-oidc "${WIF_PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location=global \
      --workload-identity-pool="${WIF_POOL_ID}" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="${ATTRIBUTE_MAPPING}" \
      --attribute-condition="${ATTRIBUTE_CONDITION}"
  else
    info "creating OIDC provider"
    gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location=global \
      --workload-identity-pool="${WIF_POOL_ID}" \
      --display-name="GitHub OIDC" \
      --description="OIDC provider for ${GITHUB_REPO} only. Attribute condition pins assertion.repository." \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="${ATTRIBUTE_MAPPING}" \
      --attribute-condition="${ATTRIBUTE_CONDITION}"
  fi
fi

WIF_PROVIDER_RESOURCE="$(gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location=global \
  --workload-identity-pool="${WIF_POOL_ID}" \
  --format='value(name)')"

# ---------------------------------------------------------------------------
# 4. terraform-deployer service account, roles, WIF binding
# ---------------------------------------------------------------------------

log "Ensuring service account ${SA_EMAIL}"
if sa_exists; then
  info "service account already exists"
else
  info "creating service account (no JSON keys will be created)"
  gcloud iam service-accounts create "${SA_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="Terraform deployer" \
    --description="GitHub Actions deployer via WIF. No JSON keys. Do not grant Owner."
fi

log "Granting project roles to ${SA_EMAIL}"
for role in "${DEPLOYER_ROLES[@]}"; do
  if project_has_role "${role}"; then
    info "already granted: ${role}"
  else
    info "granting:        ${role}"
    grant_project_role "${role}"
  fi
done

log "Binding roles/iam.workloadIdentityUser for ${GITHUB_REPO}"
if sa_has_wif_binding; then
  info "binding already present"
else
  info "member: ${WIF_MEMBER}"
  gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${WIF_MEMBER}" \
    --condition=None \
    --quiet >/dev/null
fi

# ---------------------------------------------------------------------------
# 5. GitHub repository variables to add
# ---------------------------------------------------------------------------

cat <<EOF

========================================================================
Bootstrap complete. Add these GitHub repository VARIABLES
(Settings → Secrets and variables → Actions → Variables).

None of these are credentials. That is the point of Workload Identity
Federation — do not upload a service-account JSON key.

  GCP_WIF_PROVIDER    ${WIF_PROVIDER_RESOURCE}
  GCP_DEPLOYER_SA     ${SA_EMAIL}
  GCP_PROJECT_ID      ${PROJECT_ID}
  GCP_REGION          ${REGION}
  TF_STATE_BUCKET     ${STATE_BUCKET}

Also create a GitHub Environment named "prod" with required reviewers;
the apply workflow gates on it.

If you use the gh CLI from this checkout:

  gh variable set GCP_WIF_PROVIDER --body "${WIF_PROVIDER_RESOURCE}"
  gh variable set GCP_DEPLOYER_SA  --body "${SA_EMAIL}"
  gh variable set GCP_PROJECT_ID   --body "${PROJECT_ID}"
  gh variable set GCP_REGION       --body "${REGION}"
  gh variable set TF_STATE_BUCKET  --body "${STATE_BUCKET}"

Teardown: see docs/gcp-bootstrap.md
========================================================================
EOF
