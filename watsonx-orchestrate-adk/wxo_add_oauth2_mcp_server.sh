#!/usr/bin/env bash
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Load environment variables first so every subsequent command inherits them ─
if [ -f ".env" ]; then
  set -a; source ".env"; set +a
fi

clear
echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Add the list flights tool from the Booking MCP Server (OAuth2) to watsonx Orchestrate Developer Edition ${NC}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating virtual environment... ${NC}"
source .venv/bin/activate

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Environment variables loaded from .env${NC}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating local environment watsonx Orchestrate configuration ...${NC}"
orchestrate env activate local

# Detect local network IP (macOS only; warns on other platforms)
IP_LOCAL_NETWORK_ADDRESS=$(ipconfig getifaddr en0 2>/dev/null)
if [[ -z "${IP_LOCAL_NETWORK_ADDRESS}" ]]; then
  echo -e "${RED}WARNING: could not detect local IP via 'ipconfig getifaddr en0'. Set IP_LOCAL_NETWORK_ADDRESS manually.${NC}"
  exit 1
fi

# Base URL (no path) used for the connection credential
export MCP_REMOTE_BASE_SERVER_URL="http://${IP_LOCAL_NETWORK_ADDRESS}:8084"
# Full MCP endpoint URL used for the toolkit import
export MCP_REMOTE_SERVER_URL="${MCP_REMOTE_BASE_SERVER_URL}/mcp"
# Keycloak token endpoint — MUST use the same hostname as KEYCLOAK_PUBLIC_BASE_URL
# in local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env
export TOKEN_URL="http://${IP_LOCAL_NETWORK_ADDRESS}:8086/realms/galaxium/protocol/openid-connect/token"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} OAuth2 MCP config${NC}"
echo "MCP_REMOTE_BASE_SERVER_URL: ${MCP_REMOTE_BASE_SERVER_URL}"
echo "MCP_REMOTE_SERVER_URL:      ${MCP_REMOTE_SERVER_URL}"
echo "TOKEN_URL:                  ${TOKEN_URL}"

# Demo Keycloak credentials (web-app-proxy client, client_credentials grant).
# Override by setting OIDC_CLIENT_ID / OIDC_CLIENT_SECRET in .env or the environment
# before running this script, for example when using a dedicated wxo client.
# See: infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/keycloak/README.md
export OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-web-app-proxy}"
export OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET:-web-app-proxy-secret}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 1. Create a connection for the OAuth2 MCP remote server${NC}"
export APP_ID="galaxium-mcp-oauth2-server"
orchestrate connections remove --app-id ${APP_ID}
orchestrate connections add --app-id ${APP_ID}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 2. Configure the connection (oauth_auth_client_credentials_flow)${NC}"
# watsonx Orchestrate does NOT support oauth_auth_implicit_flow for Remote MCP toolkits.
# Always use oauth_auth_client_credentials_flow for machine-to-machine MCP connections.
# Ref: https://developer.watson-orchestrate.ibm.com/connections/overview#support-by-tool-type
export ENVIRONMENT="draft"
export TYPE="team"
export KIND="oauth_auth_client_credentials_flow"
orchestrate connections configure \
  --app-id ${APP_ID} \
  --env ${ENVIRONMENT} \
  --kind ${KIND} \
  --type ${TYPE} \
  --url ${MCP_REMOTE_BASE_SERVER_URL}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 3. Set the OAuth2 credentials (client_credentials)${NC}"
# TOKEN_URL hostname must match KEYCLOAK_PUBLIC_BASE_URL used when starting the stack.
# Using localhost here while the MCP stack is started with the LAN IP will cause
# "Invalid issuer" errors because Keycloak embeds KEYCLOAK_PUBLIC_BASE_URL into the
# token's 'iss' claim, and the MCP server validates 'iss' against OIDC_ISSUER.
orchestrate connections set-credentials \
  --app-id ${APP_ID} \
  --environment ${ENVIRONMENT} \
  --client-id ${OIDC_CLIENT_ID} \
  --client-secret ${OIDC_CLIENT_SECRET} \
  --token-url ${TOKEN_URL}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 4. Import the tools from the OAuth2 MCP server${NC}"
export NAME="Galaxium-Travels-Booking-MCP-oauth2"
export DESCRIPTION="Galaxium Travels Booking MCP imported through OAuth2 client credentials."
export MCP_KIND="mcp"
export TRANSPORT="streamable_http"
export TOOLS="list_flights"
echo "MCP_REMOTE_SERVER_URL: ${MCP_REMOTE_SERVER_URL}"
orchestrate toolkits remove --name ${NAME}
orchestrate toolkits list
orchestrate toolkits add \
  --kind ${MCP_KIND} \
  --name ${NAME} \
  --description "${DESCRIPTION}" \
  --transport ${TRANSPORT} \
  --tools ${TOOLS} \
  --url ${MCP_REMOTE_SERVER_URL} \
  --app-id ${APP_ID}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW}  5. Open watsonx Orchestrate Lite Chat${NC}"
echo -e "${YELLOW} # http://localhost:3000${NC}"
echo -e "${YELLOW} #######################${NC}"
echo -e "${YELLOW}  - Visit 'Manage Agents'${NC}"
echo -e "${YELLOW}  - Ensure the 'list_flights' tool is available${NC}"
echo -e "${YELLOW}  - Add the tool to an agent${NC}"
echo -e "${YELLOW}  - Ask the question: Which flights are available?${NC}"
echo -e "${YELLOW} ######################${NC}"
echo -e "${YELLOW}  APP_ID:               ${APP_ID}${NC}"
echo -e "${YELLOW}  ENVIRONMENT:          ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}  TEAM TYPE:            ${TYPE}${NC}"
echo -e "${YELLOW}  CONNECTION KIND:      ${KIND}${NC}"
echo -e "${YELLOW}  TOKEN_URL:            ${TOKEN_URL}${NC}"
echo -e "${YELLOW}  MCP_REMOTE_SERVER_URL:${MCP_REMOTE_SERVER_URL}${NC}"
echo -e "${NC}"
