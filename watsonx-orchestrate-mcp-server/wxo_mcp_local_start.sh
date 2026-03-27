# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Starting watsonx Orchestrate MCP Server ${NC}"
clear 

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating Pythonvirtual environment... ${NC}"
source .venv/bin/activate

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Loading environment variables... ${NC}"
source .env


echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} watsonx Orchestrate MCP Server configuration... ${NC}"
echo "HOST:${WXO_MCP_HOST}\nPORT:\n${WXO_MCP_PORT}\nTRANPORT:${WXO_MCP_TRANSPORT}\nDIRECTORY:${WXO_MCP_WORKING_DIRECTORY}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Start watsonx Orchestrate MCP Server... ${NC}"
ibm-watsonx-orchestrate-mcp-server

