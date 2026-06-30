#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# start.sh – launch the watsonx Orchestrate Custom Explorer
#
# IMPORTANT: this script reuses the .venv from the parent
#   watsonx-orchestrate-mcp-server/ directory because that venv already
#   has ibm-watsonx-orchestrate (the SDK) installed. Flask and flask-cors
#   are installed into that same venv on first run.
#
# Run from inside: watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer/
# ---------------------------------------------------------------------------
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The parent dir is watsonx-orchestrate-mcp-server/ which owns the SDK venv
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PARENT_DIR/.venv"

cd "$SCRIPT_DIR"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW}  watsonx Orchestrate Custom Explorer   ${NC}"
echo -e "${BLUE}========================================${NC}"

# ── virtual environment ────────────────────────────────────────────────────
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}ERROR: SDK venv not found at $VENV_DIR${NC}"
    echo -e "${RED}Run the watsonx-orchestrate-mcp-server setup first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Activating SDK virtual environment: $VENV_DIR${NC}"
source "$VENV_DIR/bin/activate"

echo -e "${YELLOW}Installing / upgrading Explorer dependencies into SDK venv...${NC}"
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

# ── environment variables ──────────────────────────────────────────────────
if [ -f ".env" ]; then
    echo -e "${YELLOW}Loading .env...${NC}"
    source .env
elif [ -f ".env_template" ]; then
    echo -e "${RED}WARNING: .env not found – using .env_template defaults.${NC}"
    source .env_template
fi

# ── resolve MCP host ───────────────────────────────────────────────────────
# WXO_MCP_BASE_URL defaults to 127.0.0.1 but the MCP server binds to the
# LAN IP set by WXO_MCP_HOST in the parent .env (ipconfig getifaddr en0).
# Derive the real host from the parent .env so the URL is always correct.
PARENT_ENV="$PARENT_DIR/.env"
if [ -f "$PARENT_ENV" ]; then
    # Extract WXO_MCP_HOST and WXO_MCP_PORT from the parent .env
    MCP_HOST_EXPR=$(grep 'WXO_MCP_HOST' "$PARENT_ENV" | tail -1 | sed 's/.*=//;s/export //')
    MCP_PORT_EXPR=$(grep 'WXO_MCP_PORT' "$PARENT_ENV" | tail -1 | sed 's/.*=//;s/export //')
    # Evaluate – handles $(ipconfig getifaddr en0) style values
    RESOLVED_HOST=$(eval echo "$MCP_HOST_EXPR" 2>/dev/null || true)
    RESOLVED_PORT=$(eval echo "$MCP_PORT_EXPR" 2>/dev/null || echo "8080")
    if [ -n "$RESOLVED_HOST" ] && [ "$RESOLVED_HOST" != "127.0.0.1" ]; then
        export WXO_MCP_BASE_URL="http://${RESOLVED_HOST}:${RESOLVED_PORT}"
    fi
fi

echo -e "${GREEN}WXO_MCP_BASE_URL : ${WXO_MCP_BASE_URL:-http://127.0.0.1:8080}${NC}"
echo -e "${GREEN}EXPLORER_PORT    : ${EXPLORER_PORT:-5001}${NC}"

# ── launch Flask ───────────────────────────────────────────────────────────
echo -e "\n${BLUE}========================================${NC}"
echo -e "${YELLOW}  Starting Flask on port ${EXPLORER_PORT:-5001}...${NC}"
echo -e "${BLUE}========================================${NC}"
python3 src/app.py
