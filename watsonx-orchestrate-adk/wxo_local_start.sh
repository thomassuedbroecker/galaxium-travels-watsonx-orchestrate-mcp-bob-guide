#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
info() { echo -e "${YELLOW}[..] $*${NC}"; }
fail() { echo -e "${RED}[!!] $*${NC}" >&2; exit 1; }

# ── 1. venv + credentials ─────────────────────────────────────────────────────
source .venv/bin/activate
source .env
ok "venv active — $(orchestrate --version | head -1)"

# Warn if OTEL tracing label is missing (upstream addition)
if [[ -z "${OTEL_SERVICE_NAME:-}" ]]; then
  echo -e "${YELLOW}[warn] OTEL_SERVICE_NAME not set — trace spans will show 'unknown_service'${NC}"
  echo -e "${GREEN}       Fix: add 'export OTEL_SERVICE_NAME=wxo-agent-runtime' to .env${NC}"
fi

# ── 2. start server ───────────────────────────────────────────────────────────
info "Resetting server config"
orchestrate server reset

info "Starting watsonx Orchestrate Developer Edition"
orchestrate server start \
  --env-file .env \
  --with-connections-ui \
  --accept-terms-and-conditions \
  --with-ibm-telemetry

# ── 3. wait for ready ─────────────────────────────────────────────────────────
info "Waiting for server on :4321"
for i in {1..12}; do
  curl -sf http://localhost:4321/api/v1/auth/token >/dev/null && break
  [[ $i -eq 12 ]] && fail "Server not ready after 60 s — run: orchestrate server purge"
  echo "  attempt $i/12…"; sleep 5
done
ok "Server ready"

# ── 4. configure environment + watsonx.ai connection ─────────────────────────
orchestrate env activate local

orchestrate connections add -a watsonx_credentials 2>/dev/null || true
orchestrate connections configure -a watsonx_credentials --env draft -k key_value -t team
orchestrate connections set-credentials -a watsonx_credentials --env draft -e "api_key=${WATSONX_APIKEY}"
ok "watsonx_credentials connection set"

# ── 5. generate model YAMLs and import ───────────────────────────────────────
for tmpl in ./model-configs/*.yaml_template; do
  yaml="${tmpl%_template}"
  sed "s/YOUR_SPACE_ID/${WATSONX_SPACE_ID}/g" "$tmpl" > "$yaml"
done

orchestrate models import --file ./model-configs/model-config_llama_3_3_70b_instruct.yaml --app-id watsonx_credentials
orchestrate models import --file ./model-configs/model-config_openai_gpt_oss_120b.yaml     --app-id watsonx_credentials
ok "Models imported"

# ── 6. smoke-test agent ───────────────────────────────────────────────────────
orchestrate agents import -f ./agents/agent_hello_world.yaml
ok "Hello-world agent imported"

# ── 7. done ───────────────────────────────────────────────────────────────────
echo ""
ok "Stack is up — open http://localhost:3000 to chat"
echo "   Run 'orchestrate chat start' to open LiteChat in the browser"
echo "   Run 'bash customization/implementations/agents/deploy_agent.sh' to deploy the Galaxium agent"
