# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Verify environment ${NC}"
clear 

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating Pythonvirtual environment... ${NC}"
source .venv/bin/activate

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Verify watsonx Orchestrate version... ${NC}"
orchestrate --version

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Set environments variables...${NC}"
source .env

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Starting watsonx Orchestrate Development Edition ${NC}"
clear 

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Running watsonx Orchestrate server reset...${NC}"
orchestrate server reset
cat ~/.cache/orchestrate/merged.env

echo "Press any key to move on:"
read ANY_KEY
rm ~/.cache/orchestrate/merged.env

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Start local Orchestrate server using _watsonx.ai for the models._${NC}"
orchestrate server start --env-file .env --with-connections-ui --accept-terms-and-conditions --with-langfuse

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Waiting for Orchestrate server to be ready on port 4321...${NC}"
until curl -s http://localhost:4321/api/v1/auth/token > /dev/null 2>&1; do
  sleep 5
  CURRENT=$((j++))
  echo -e "  ${YELLOW}... $CURRENT waiting${NC}"
  STOP=5
  SERVER_READY=1
  if [[ $CURRENT -eq $STOP ]]; then
    echo -e "  ${RED}Server NOT ready!${NC}"
    echo -e "  ${RED}You need to start the bash automation again.${NC}"
    SERVER_READY=0
    echo -e "  ${RED}Should I delete the VM machine?(Y/N)${NC}"
    read ANSWER
    if [[ $ANSWER -eq "Y" ]]; then
      orchestrate server purge
      echo -e "  ${RED}VM is deleted.${NC}"
    fi
    if [[ $ANSWER -eq "N" ]]; then
      echo -e "  ${YELLOW}VM NOT deleted.${NC}"
    fi
    exit 0
  fi
done
if [[ $SERVER_READY -eq 1 ]]; then
    echo -e "  ${GREEN}Server is ready.${NC}"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Activating local environment watsonx Orchestrate configuration ...${NC}"
orchestrate env activate local

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} List models for watsonx Orchestrate... ${NC}"
orchestrate models list -a

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Set connection to import watsonx.ai models ...${NC}"
orchestrate connections add -a watsonx_credentials
orchestrate connections configure -a watsonx_credentials --env draft -k key_value -t team
orchestrate connections set-credentials -a watsonx_credentials --env draft -e "api_key=${WATSONX_APIKEY}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Convert model config templates to YAML files...${NC}"
for template in ./model-configs/*.yaml_template; do
  yaml="${template%_template}"
  sed "s/YOUR_SPACE_ID/${WATSONX_SPACE_ID}/g" "$template" > "$yaml"
  echo -e "  ${GREEN}Created:${NC} $yaml"
done

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Import models from watsonx.ai ...${NC}"
orchestrate models import --file ./model-configs/model-config_llama_3_3_70b_instruct.yaml --app-id watsonx_credentials
orchestrate models import --file ./model-configs/model-config_openai_gpt_oss_120b.yaml --app-id watsonx_credentials

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Import agent from agents/agent_hello_world.yaml ...${NC}"
orchestrate agents import -f ./agents/agent_hello_world.yaml

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Starting local Orchestrate chat... ${NC}"
orchestrate chat start

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} watsonx Orchestrate MCP Server config... ${NC}"
echo "HOST:${WXO_MCP_HOST}\nPORT:\n${WXO_MCP_PORT}\nTRANPORT:${WXO_MCP_TRANSPORT}\nDIRECTORY:${WXO_MCP_WORKING_DIRECTORY}"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW} Start watsonx Orchestrate MCP Server config... ${NC}"
cd ../watsonx-orchestrate-mcp-server/ibm-watsonx-orchestrate-mcp-server
