# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Starting watsonx Orchestrate Development Edition ${NC}"
clear 

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating Pythonvirtual environment... ${NC}"
source .venv/bin/activate

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Running watsonx Orchestrate server reset...${NC}"
orchestrate server reset

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Set environments variables...${NC}"
source .env

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Start local Orchestrate server using _watsonx.ai for the models._${NC}"
orchestrate server start --env-file .env --with-connections-ui --accept-terms-and-conditions --with-langfuse

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating local environment watsonx Orchestrate configuration ...${NC}"
orchestrate env activate local

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Starting local Orchestrate chat... ${NC}"
orchestrate chat start

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} watsonx Orchestrate MCP Server config... ${NC}"
echo "HOST:${WXO_MCP_HOST}\nPORT:\n${WXO_MCP_PORT}\nTRANPORT:${WXO_MCP_TRANSPORT}\nDIRECTORY:${WXO_MCP_WORKING_DIRECTORY}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Start watsonx Orchestrate MCP Server config... ${NC}"
../watsonx-orchestrate-mcp-server/ibm-watsonx-orchestrate-mcp-server

