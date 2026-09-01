#!/usr/bin/env bash
# =============================================================================
# deploy_agent.sh
#
# End-to-end deployment of the Galaxium Travels booking agent into a running
# watsonx Orchestrate Developer Edition instance.
#
# Pre-conditions
#   1. Infrastructure containers are running (docker-compose basic-auth-vm stack)
#   2. watsonx Orchestrate Developer Edition is running
#      (started with: orchestrate server start --env-file .env ...)
#   3. Run this script from the repository root:
#        bash customization/implementations/agents/deploy_agent.sh
#
# What this script does (in order)
#   1.  Activates the ADK Python virtual environment
#   2.  Loads ADK environment variables from watsonx-orchestrate-adk/.env
#   3.  Activates the local orchestrate environment
#   4.  Detects the host LAN IP (used so the WXO Lima VM can reach the MCP server)
#   5.  Verifies the Galaxium MCP server is reachable with Basic Auth
#   6.  Registers (or re-registers) the Basic Auth connection
#   7.  Imports the complete Galaxium MCP toolkit (all 6 tools)
#   8.  Imports the Galaxium booking agent YAML
#   9.  Patches the Galaxium booking web app (port 8085) with the embedded
#       watsonx Orchestrate agent URL so the "Ask AI" button works
#  10.  Prints a summary of what was deployed
# =============================================================================

set -euo pipefail

# ─── colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
_fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ─── paths ───────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ADK_DIR="${REPO_ROOT}/watsonx-orchestrate-adk"
ADK_ENV="${ADK_DIR}/.env"
ADK_VENV="${ADK_DIR}/.venv"
AGENT_YAML="${REPO_ROOT}/customization/configurations/agents/galaxium_booking_agent.yaml"

# ─── Step 1 — activate venv ──────────────────────────────────────────────────
_info "Step 1 — Activating ADK virtual environment"
if [[ ! -f "${ADK_VENV}/bin/activate" ]]; then
  _fail "ADK venv not found at ${ADK_VENV}. Run: python3 -m venv ${ADK_VENV} && pip install ibm-watsonx-orchestrate==2.12.0"
fi
# shellcheck disable=SC1090
source "${ADK_VENV}/bin/activate"
_ok "venv active — $(orchestrate --version | head -1)"

# ─── Step 2 — load env vars ──────────────────────────────────────────────────
_info "Step 2 — Loading environment variables from ${ADK_ENV}"
if [[ ! -f "${ADK_ENV}" ]]; then
  _fail ".env not found at ${ADK_ENV}. Copy .env_template and fill in your credentials."
fi
# shellcheck disable=SC1090
source "${ADK_ENV}"

# Validate required credentials
for var in WO_ENTITLEMENT_KEY WATSONX_APIKEY WATSONX_SPACE_ID; do
  val="${!var:-}"
  if [[ -z "${val}" || "${val}" == *"<"* ]]; then
    _fail "${var} is not set or still contains a placeholder. Edit ${ADK_ENV}."
  fi
done
_ok "Credentials loaded"

# ─── Step 3 — activate local env ─────────────────────────────────────────────
_info "Step 3 — Activating watsonx Orchestrate local environment"
orchestrate env activate local
_ok "Local environment active"

# ─── Step 4 — detect host LAN IP ─────────────────────────────────────────────
_info "Step 4 — Detecting host LAN IP"
LOCAL_NET_IP=$(ipconfig getifaddr en0 2>/dev/null || true)
if [[ -z "${LOCAL_NET_IP}" ]]; then
  # Fallback: first non-loopback IPv4
  LOCAL_NET_IP=$(ifconfig | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}')
fi
if [[ -z "${LOCAL_NET_IP}" ]]; then
  _fail "Cannot detect LAN IP. Set LOCAL_NET_IP manually and re-run."
fi
MCP_BASE_URL="http://${LOCAL_NET_IP}:8084"
MCP_ENDPOINT="${MCP_BASE_URL}/mcp"
_ok "LAN IP: ${LOCAL_NET_IP}"
_ok "MCP base URL:     ${MCP_BASE_URL}"
_ok "MCP endpoint URL: ${MCP_ENDPOINT}"

# ─── Step 5 — verify MCP reachability ────────────────────────────────────────
_info "Step 5 — Verifying Galaxium MCP server is reachable"
BASIC_TOKEN="$(printf '%s' "demo-basic-user:demo-basic-password" | base64 | tr -d '\r\n')"

INIT_RESP=$(curl -si \
  --max-time 10 \
  -X POST "${MCP_ENDPOINT}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"deploy-check","version":"1.0"}}}' \
  2>/dev/null || true)

HTTP_CODE=$(echo "${INIT_RESP}" | grep -E "^HTTP" | awk '{print $2}')
if [[ "${HTTP_CODE}" != "200" ]]; then
  _fail "MCP server at ${MCP_ENDPOINT} returned HTTP ${HTTP_CODE:-unreachable}. Ensure the infrastructure stack is running."
fi
_ok "MCP server responded HTTP 200"

# ─── Step 6 — register the Basic Auth connection ─────────────────────────────
_info "Step 6 — Registering Basic Auth connection"
APP_ID="galaxium-mcp-remote-server"
ENVIRONMENT="draft"

orchestrate connections remove --app-id "${APP_ID}" 2>/dev/null || true
orchestrate connections add --app-id "${APP_ID}"
orchestrate connections configure \
  --app-id "${APP_ID}" \
  --env "${ENVIRONMENT}" \
  --kind basic \
  --type team \
  --url "${MCP_BASE_URL}"
orchestrate connections set-credentials \
  --app-id "${APP_ID}" \
  --environment "${ENVIRONMENT}" \
  --username "demo-basic-user" \
  --password "demo-basic-password"
_ok "Connection '${APP_ID}' registered with Basic Auth"

# ─── Step 7 — import the MCP toolkit (all 6 tools) ───────────────────────────
_info "Step 7 — Importing Galaxium MCP toolkit"
TOOLKIT_NAME="Galaxium-Travels-Booking-MCP-remote"
ALL_TOOLS="list_flights,book_flight,get_bookings,cancel_booking,register_user,get_user_id"

orchestrate toolkits remove --name "${TOOLKIT_NAME}" 2>/dev/null || true

# Try with --app-id first (ADK ≥ 2.12.0); fall back without it if rejected
if orchestrate toolkits add \
    --kind mcp \
    --name "${TOOLKIT_NAME}" \
    --description "Galaxium Travels Booking MCP imported through Basic Auth." \
    --transport streamable_http \
    --tools "${ALL_TOOLS}" \
    --url "${MCP_ENDPOINT}" \
    --app-id "${APP_ID}" 2>/dev/null; then
  _ok "Toolkit '${TOOLKIT_NAME}' imported (with --app-id)"
else
  _warn "--app-id flag rejected by CLI — retrying without it"
  orchestrate toolkits add \
    --kind mcp \
    --name "${TOOLKIT_NAME}" \
    --description "Galaxium Travels Booking MCP imported through Basic Auth." \
    --transport streamable_http \
    --tools "${ALL_TOOLS}" \
    --url "${MCP_ENDPOINT}"
  _ok "Toolkit '${TOOLKIT_NAME}' imported (without --app-id)"
fi

# ─── Step 8 — generate model YAMLs and import agent ─────────────────────────
_info "Step 8 — Generating model YAML files and importing booking agent"

# Generate model configs with real space ID
for template in "${ADK_DIR}"/model-configs/*.yaml_template; do
  yaml="${template%_template}"
  sed "s/YOUR_SPACE_ID/${WATSONX_SPACE_ID}/g" "${template}" > "${yaml}"
done
_ok "Model YAML files generated"

# Import models (ignore errors if already imported)
orchestrate models import \
  --file "${ADK_DIR}/model-configs/model-config_llama_3_3_70b_instruct.yaml" \
  --app-id watsonx_credentials 2>/dev/null || _warn "Llama model already imported or import failed — continuing"

# Import the booking agent
orchestrate agents import -f "${AGENT_YAML}"
_ok "Booking agent 'galaxium_booking_agent' imported"

# ─── Step 9 — configure embedded agent in the web app ────────────────────────
_info "Step 9 — Configuring embedded agent integration in the Galaxium web app"

# The MCP web UI container (port 8085) supports an optional embedded agent.
# We inject the watsonx Orchestrate LiteChat URL so the "Ask AI" button in
# the UI points at the booking agent.
#
# The integration is done by updating the running container's environment
# variable WXO_AGENT_EMBED_URL. The compose file does not set this variable
# by default, so we restart the container with the new setting.

EMBED_URL="http://localhost:3000"
CONTAINER_NAME="web_app_mcp_basic_vm"

if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
  # Restart with the embed URL env var so the UI shows the "Ask AI" panel
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1

  docker run -d \
    --name "${CONTAINER_NAME}" \
    --network galaxium-travels-infrastructure-tsuedbro_mcp-network \
    -p 8085:8085 \
    -e PORT=8085 \
    -e MCP_SERVER_URL="http://booking_system_mcp:8084/mcp" \
    -e MCP_TIMEOUT_SECONDS=10 \
    -e BACKEND_AUTH_MODE=basic \
    -e BASIC_AUTH_USERNAME=demo-basic-user \
    -e BASIC_AUTH_PASSWORD=demo-basic-password \
    -e FRONTEND_AUTH_REQUIRED=false \
    -e WXO_AGENT_EMBED_URL="${EMBED_URL}" \
    web_app_mcp:1.0.0

  _ok "web_app_mcp container restarted with WXO_AGENT_EMBED_URL=${EMBED_URL}"
else
  _warn "Container '${CONTAINER_NAME}' not found — skipping embedded agent restart"
fi

# ─── Step 10 — summary ───────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Galaxium Travels Booking Agent — Deployment Done  ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}Deployed objects:${NC}"
echo -e "    Connection  : ${APP_ID} (Basic Auth → ${MCP_BASE_URL})"
echo -e "    Toolkit     : ${TOOLKIT_NAME}"
echo -e "    Tools       : ${ALL_TOOLS//,/  •  }"
echo -e "    Agent       : galaxium_booking_agent"
echo ""
echo -e "  ${BLUE}Open in browser:${NC}"
echo -e "    LiteChat (talk to the agent)   → http://localhost:3000"
echo -e "    Galaxium MCP web UI            → http://localhost:8085"
echo -e "    Booking REST API docs          → http://localhost:8082/docs"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo -e "    1. Open http://localhost:3000"
echo -e "    2. Select the 'galaxium_booking_agent'"
echo -e "    3. Ask: 'Which flights are available?'"
echo ""
