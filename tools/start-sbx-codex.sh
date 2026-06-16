#!/usr/bin/env bash 
set -Eeuo pipefail

# Docker Sandbox (sbx) wrapper for using coding agents with local LLM
# (Compatible with sbx version: v0.32.0 )

# ---- User-configurable defaults ---------------------------------------------

WORKSPACE="${WORKSPACE:-$(pwd)}"

# Derive a stable sandbox name from the workspace directory name.
# Example:
#   /home/me/projects/my-api -> my-api-codex-local
WORKSPACE_ABS="$(cd "$WORKSPACE" && pwd -P)"
WORKSPACE_DIR_NAME="$(basename "$WORKSPACE_ABS")"

# Make it safe-ish for sbx names: lowercase, replace unsupported chars with "-".
WORKSPACE_SLUG="$(
  printf '%s' "$WORKSPACE_DIR_NAME" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//'
)"

WORKSPACE_SLUG="${WORKSPACE_SLUG:-workspace}"

SANDBOX_NAME="${SANDBOX_NAME:-${WORKSPACE_SLUG}-codex-local}"

# Host-side llama.cpp / proxy port.
LLM_PORT="${LLM_PORT:-8080}"

# Host URL used from the host itself.
HOST_LLM_BASE_URL="${HOST_LLM_BASE_URL:-http://127.0.0.1:${LLM_PORT}/v1}"

# Sandbox URL used from inside Docker Sandbox.
SBX_LLM_BASE_URL="${SBX_LLM_BASE_URL:-http://host.docker.internal:${LLM_PORT}/v1}"

# Must match the llama.cpp --alias value, or the model id returned by /v1/models.
CODEX_MODEL="${CODEX_MODEL:-local-coder}"

# Provider name inside Codex config.
CODEX_PROVIDER="${CODEX_PROVIDER:-llamacpp}"

# For current Codex this should normally be "responses".
# Raw llama.cpp may only support "chat", but Codex chat support is being phased out.
CODEX_WIRE_API="${CODEX_WIRE_API:-responses}"

# Codex will read this env var for provider auth.
CODEX_API_KEY_ENV="${CODEX_API_KEY_ENV:-LOCAL_LLM_API_KEY}"
CODEX_API_KEY_VALUE="${CODEX_API_KEY_VALUE:-dummy}"

# Whether to bypass Codex's own sandbox/approval layer because sbx is the outer sandbox.
CODEX_BYPASS="${CODEX_BYPASS:-1}"

# Set to 1 to only prepare the sandbox/config and not start Codex.
PREPARE_ONLY="${PREPARE_ONLY:-0}"

# Extra args passed to Codex.
CODEX_ARGS=("$@")

# ---- Helpers ----------------------------------------------------------------

log() {
  printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

curl_json() {
  local url="$1"
  if command -v jq >/dev/null 2>&1; then
    curl -fsS "$url" | jq
  else
    curl -fsS "$url"
    echo
  fi
}

sandbox_exists() {
  sbx ls -q | grep -Fxq "$SANDBOX_NAME"
}

# ---- Preconditions ----------------------------------------------------------

need_cmd sbx
need_cmd curl

log "Checking host-side local model endpoint: ${HOST_LLM_BASE_URL}/models"
curl_json "${HOST_LLM_BASE_URL}/models" >/dev/null

# ---- Create/reuse sandbox ---------------------------------------------------

if sandbox_exists; then
  log "Reusing existing sandbox: ${SANDBOX_NAME}"
else
  log "Creating Codex sandbox: ${SANDBOX_NAME}"
  sbx create codex "$WORKSPACE" --name "$SANDBOX_NAME"
fi

# ---- Allow sandbox to reach host-side model endpoint ------------------------

log "Allowing sandbox network access to localhost:${LLM_PORT}"
sbx policy allow network --sandbox "$SANDBOX_NAME" "localhost:${LLM_PORT}"

log "Checking model endpoint from inside sandbox: ${SBX_LLM_BASE_URL}/models"
sbx exec "$SANDBOX_NAME" bash -lc "curl -fsS '${SBX_LLM_BASE_URL}/models' >/dev/null"

# ---- Write Codex config inside sandbox --------------------------------------

log "Writing Codex config inside sandbox"

sbx exec "$SANDBOX_NAME" bash -lc "sudo tee ~/.codex/config.toml <<'EOF'
model = \"${CODEX_MODEL}\"
model_provider = \"${CODEX_PROVIDER}\"

approval_policy = \"on-request\"
sandbox_mode = \"workspace-write\"

[model_providers.${CODEX_PROVIDER}]
name = \"${CODEX_PROVIDER}\"
base_url = \"${SBX_LLM_BASE_URL}\"
env_key = \"${CODEX_API_KEY_ENV}\"
wire_api = \"${CODEX_WIRE_API}\"

request_max_retries = 2
stream_max_retries = 2
stream_idle_timeout_ms = 300000
EOF"

log "Current sandbox Codex config:"
sbx exec "$SANDBOX_NAME" bash -lc "cat ~/.codex/config.toml"

if [[ "$PREPARE_ONLY" == "1" ]]; then
  log "Prepared only. Not starting Codex."
  exit 0
fi

# ---- Start Codex ------------------------------------------------------------

log "Starting Codex in sandbox: ${SANDBOX_NAME}"

CODEX_CMD=(codex)

if [[ "$CODEX_BYPASS" == "1" ]]; then
  CODEX_CMD+=(--dangerously-bypass-approvals-and-sandbox)
fi

if [[ "${#CODEX_ARGS[@]}" -gt 0 ]]; then
  CODEX_CMD+=("${CODEX_ARGS[@]}")
fi

sbx exec -it \
  -e "${CODEX_API_KEY_ENV}=${CODEX_API_KEY_VALUE}" \
  -w ${WORKSPACE} \
  "$SANDBOX_NAME" \
  "${CODEX_CMD[@]}"