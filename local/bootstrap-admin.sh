#!/usr/bin/env bash
# Mint a one-time first-admin invite for the local Compose harness.
#
# The Paperclip UI suggests `pnpm paperclipai auth bootstrap-ceo` on the host,
# but this repo has no Paperclip source tree. For Docker, run the CLI *inside*
# the paperclip container instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing local/.env — copy from .env.example first." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

PUBLIC_URL="${PAPERCLIP_PUBLIC_URL:-http://localhost:${PAPERCLIP_HOST_PORT:-3100}}"
CONFIG_PATH="${PAPERCLIP_CONFIG:-/paperclip/instances/default/config.json}"

# The server can boot from env alone and never writes config.json. The CLI still
# requires one, so seed a minimal file that mirrors this harness's env.
docker compose --env-file .env exec -T paperclip sh -c "
set -e
mkdir -p \"\$(dirname '$CONFIG_PATH')\"
if [ ! -f '$CONFIG_PATH' ]; then
  cat > '$CONFIG_PATH' <<'EOF'
{
  \"\$meta\": {
    \"version\": 1,
    \"updatedAt\": \"2026-08-10T00:00:00.000Z\",
    \"source\": \"configure\"
  },
  \"database\": {
    \"mode\": \"postgres\",
    \"connectionString\": \"postgres://paperclip:paperclip@db:5432/paperclip\",
    \"backup\": { \"enabled\": false }
  },
  \"logging\": {
    \"mode\": \"file\",
    \"logDir\": \"/paperclip/instances/default/logs\"
  },
  \"server\": {
    \"deploymentMode\": \"authenticated\",
    \"exposure\": \"public\",
    \"bind\": \"lan\",
    \"host\": \"0.0.0.0\",
    \"port\": 3100,
    \"serveUi\": true
  },
  \"auth\": {
    \"baseUrlMode\": \"explicit\",
    \"publicBaseUrl\": \"http://localhost:3100\",
    \"disableSignUp\": false
  },
  \"storage\": {
    \"provider\": \"s3\",
    \"s3\": {
      \"bucket\": \"paperclip-uploads\",
      \"region\": \"us-east-1\",
      \"endpoint\": \"http://minio:9000\",
      \"forcePathStyle\": true,
      \"prefix\": \"uploads\"
    }
  },
  \"secrets\": {
    \"provider\": \"local_encrypted\",
    \"strictMode\": false
  },
  \"telemetry\": { \"enabled\": false }
}
EOF
fi
cd /app
pnpm paperclipai auth bootstrap-ceo --config '$CONFIG_PATH' --base-url '$PUBLIC_URL'
"
