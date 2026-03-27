# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Add the list flights tool from the Booking MCP Server the to watsonx Orchestrate Development Edition ${NC}"
clear 

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating virtual environment... ${NC}"
source .venv/bin/activate

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Set environments variables...${NC}"
source .env

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating local environment watsonx Orchestrate configuration ...${NC}"
orchestrate env activate local

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} watsonx Orchestrate MCP Server config... ${NC}"
echo "HOST:${WXO_MCP_HOST}"
echo "PORT:${WXO_MCP_PORT}"
echo "TRANSPORT:${WXO_MCP_TRANSPORT}"
echo "DIRECTORY:${WXO_MCP_WORKING_DIRECTORY}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 1. Create a connection for the _MCP remote server_${NC}"
export APP_ID="galaxium-mcp-remote-server"
orchestrate connections remove --app-id ${APP_ID}
orchestrate connections add --app-id ${APP_ID}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 2. Configure the watsonx Orchestrate  _MCP remote server_ connection${NC}"
export ENVIRONMENT="draft"
export TYPE="team"
export KIND="basic"
export APP_ID="galaxium-mcp-remote-server"
IP_LOCAL_NETWORK_ADDRESS=$(ipconfig getifaddr en0)
export MCP_REMOTE_BASE_SERVER_URL="http://${IP_LOCAL_NETWORK_ADDRESS}:8084/mcp"
#export MCP_REMOTE_BASE_SERVER_URL="http://host.docker.internal:8084/mcp"
#export MCP_REMOTE_BASE_SERVER_URL="http://host.lima.internal:8084/mcp"
echo "MCP_REMOTE_BASE_SERVER_URL: ${MCP_REMOTE_BASE_SERVER_URL}"
orchestrate connections configure --app-id ${APP_ID} --env ${ENVIRONMENT} --kind ${KIND} --type ${TYPE} --url ${MCP_REMOTE_BASE_SERVER_URL}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 3. Configure basic authentication for the connection{NC}"
export APP_ID="galaxium-mcp-remote-server"
export ENVIRONMENT="draft"
export SERVICE_USERNAME="demo-basic-user"
export SERVICE_PASSWORD="demo-basic-password"
orchestrate connections set-credentials --app-id ${APP_ID} --environment ${ENVIRONMENT} --username ${SERVICE_USERNAME} --password ${SERVICE_PASSWORD}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} 4. Import the tools from the MCP server{NC}"
export APP_ID="galaxium-mcp-remote-server"
export NAME="Galaxium-Travels-Booking-MCP-remote"
export DESCRIPTION="Galaxium import from 'MCP server'."
export ENVIRONMENT="draft"
export TYPE="team"
export KIND="mcp"
export TRANSPORT="streamable_http"
export MCP_REMOTE_SERVER_URL="${MCP_REMOTE_BASE_SERVER_URL}"
export TOOLS=list_flights
source ./.venv/bin/activate
echo "MCP_REMOTE_SERVER_URL: ${MCP_REMOTE_SERVER_URL}"
orchestrate toolkits remove --name ${NAME}
orchestrate toolkits list
orchestrate toolkits add --kind ${KIND} --name ${NAME} --description "${DESCRIPTION}" --transport ${TRANSPORT} --tools ${TOOLS} --url ${MCP_REMOTE_SERVER_URL} --app-id ${APP_ID}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW}  8. Open watsonx Orchestrate Lite Chat${NC}"
echo -e "${YELLOW} # http://localhost:3000${NC}"
echo -e "${YELLOW} #######################${NC}"
echo -e "${YELLOW}  - Visit 'Manage Agents'${NC}"
echo -e "${YELLOW}  - Ensure the 'AllFlights Tool' is available${NC}"
echo -e "${YELLOW}  - Add 'AllFlights Tool' to an agent${NC}"
echo -e "${YELLOW}  - Ask the question: Which flights are available?${NC}"
echo -e "${YELLOW} ######################${NC}"
echo -e "${YELLOW}  APP_ID: ${APP_ID}${NC}"
echo -e "${YELLOW}  ENVIRONMENT: ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}  TEAM TYPE: ${TYPE}${NC}"
echo -e "${YELLOW}  MCP_REMOTE_SERVER_URL: ${MCP_REMOTE_SERVER_URL}${NC}"
echo -e "${NC}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW}  Server logs ${NC}"
#orchestrate server logs | grep "tools"