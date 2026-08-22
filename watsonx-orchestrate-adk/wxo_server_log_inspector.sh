#!/usr/bin/env bash
# wxo_server_log_inspector.sh
# Stream logs from every running watsonx Orchestrate server container
# in parallel and capture them to timestamped files for later analysis.
#
# Usage:
#   ./wxo_server_log_inspector.sh [--env-file <path>] [--log-dir <dir>] [--name <name>]
#
# Options:
#   --env-file  -e   Path to a .env file forwarded to `orchestrate server logs`.
#                    Defaults to .env if present.
#   --log-dir   -d   Directory where captured log files are written.
#                    Defaults to ./server-logs
#   --name      -n   Capture a specific container by name instead of all.
#   --help           Show this message and exit.

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
ENV_FILE=".env"
LOG_DIR="./server-logs"
TARGET_NAME=""
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# ── Argument parsing ──────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file|-e)  ENV_FILE="$2";    shift 2 ;;
    --log-dir|-d)   LOG_DIR="$2";     shift 2 ;;
    --name|-n)      TARGET_NAME="$2"; shift 2 ;;
    --help)
      sed -n -e '/^#!/d' -e '/^#/!q' -e 's/^# \{0,2\}//p' "$0"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      exit 1
      ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${YELLOW} $* ${NC}"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: '$1' not found. $2${NC}" >&2
    exit 1
  fi
}

# Read newline-delimited input into a plain indexed array (bash 3.2 safe).
read_into_array() {
  local _var="$1"
  local _input="$2"
  local _i=0
  local _line
  eval "${_var}=()"
  while IFS= read -r _line; do
    [ -z "$_line" ] && continue
    eval "${_var}[$_i]=\"\${_line}\""
    _i=$(( _i + 1 ))
  done <<EOF
$_input
EOF
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
require_cmd python3 "Python 3 is required to locate the bundled limactl binary"

# ── Activate venv + env vars ──────────────────────────────────────────────────
# The virtual environment must be activated before we can call `python3 -c` to
# locate the bundled limactl, and before `orchestrate` is available.
print_header "Activating virtual environment"
source .venv/bin/activate

if [ -f "${ENV_FILE}" ]; then
  print_header "Loading environment variables from ${ENV_FILE}"
  set -a; source "${ENV_FILE}"; set +a
fi

# ── Locate the bundled limactl ────────────────────────────────────────────────
# The ADK ships its own limactl inside the Python package so it does not rely
# on a system-level limactl installation.  All docker commands must go through
# it to reach containers running inside the Lima VM.
print_header "Locating bundled limactl"

LIMACTL=$(python3 -c "
import os
from importlib.resources import files
p = files('ibm_watsonx_orchestrate.developer_edition.resources.lima.bin') / 'limactl'
print(str(p))
" 2>/dev/null)

if [ -z "${LIMACTL}" ] || [ ! -f "${LIMACTL}" ]; then
  echo -e "${RED}ERROR: bundled limactl not found at: ${LIMACTL}${NC}"
  echo -e "${RED}Is the virtual environment activated and ibm-watsonx-orchestrate installed?${NC}"
  exit 1
fi

echo -e "${GREEN}Found limactl: ${LIMACTL}${NC}"

# ── Discover containers via limactl shell → docker ps ─────────────────────────
# `orchestrate server logs` has no list-only mode — it must be given a --name.
# The correct way to list containers inside the Lima VM is:
#   limactl shell ibm-watsonx-orchestrate -- docker ps --format '{{.Names}}'
print_header "Discovering running watsonx Orchestrate containers"

LIMA_VM="ibm-watsonx-orchestrate"

if [ -n "${TARGET_NAME}" ]; then
  # Verify the named container is running inside the VM.
  RUNNING=$("${LIMACTL}" shell "${LIMA_VM}" -- docker ps \
    --format '{{.Names}}' 2>/dev/null \
    | grep -F "${TARGET_NAME}" || true)
  if [ -z "${RUNNING}" ]; then
    echo -e "${RED}ERROR: container '${TARGET_NAME}' is not running inside the Lima VM.${NC}"
    echo -e "${YELLOW}Running containers:${NC}"
    "${LIMACTL}" shell "${LIMA_VM}" -- docker ps --format '  {{.Names}}' 2>/dev/null
    exit 1
  fi
  CONTAINERS=("${TARGET_NAME}")
  echo -e "${GREEN}Using specified container: ${TARGET_NAME}${NC}"
else
  RAW=$("${LIMACTL}" shell "${LIMA_VM}" -- docker ps --format '{{.Names}}' 2>/dev/null)
  if [ -z "${RAW}" ]; then
    echo -e "${RED}ERROR: no running containers found inside the Lima VM.${NC}"
    echo -e "${RED}Is the watsonx Orchestrate server running?${NC}"
    echo -e "${YELLOW}Start it with: bash wxo_local_start.sh${NC}"
    exit 1
  fi
  read_into_array CONTAINERS "${RAW}"
fi

if [ ${#CONTAINERS[@]} -eq 0 ]; then
  echo -e "${RED}No containers to capture. Is the server started?${NC}"
  exit 1
fi

echo -e "${GREEN}Found ${#CONTAINERS[@]} container(s):${NC}"
for c in "${CONTAINERS[@]}"; do
  echo -e "  ${CYAN}• ${c}${NC}"
done

# ── Prepare log directory ─────────────────────────────────────────────────────
print_header "Preparing log directory"
LOG_SESSION_DIR="${LOG_DIR}/${TIMESTAMP}"
mkdir -p "${LOG_SESSION_DIR}"
echo -e "${GREEN}Session directory: ${LOG_SESSION_DIR}${NC}"

# ── Write manifest ────────────────────────────────────────────────────────────
MANIFEST="${LOG_SESSION_DIR}/manifest.json"
LAST_IDX=$(( ${#CONTAINERS[@]} - 1 ))
{
  echo "{"
  echo "  \"timestamp\": \"${TIMESTAMP}\","
  echo "  \"env_file\": \"${ENV_FILE}\","
  echo "  \"containers\": ["
  for i in "${!CONTAINERS[@]}"; do
    COMMA=","
    [ $i -eq $LAST_IDX ] && COMMA=""
    echo "    \"${CONTAINERS[$i]}\"${COMMA}"
  done
  echo "  ],"
  echo "  \"log_files\": ["
  for i in "${!CONTAINERS[@]}"; do
    COMMA=","
    [ $i -eq $LAST_IDX ] && COMMA=""
    echo "    \"${CONTAINERS[$i]}.log\"${COMMA}"
  done
  echo "  ]"
  echo "}"
} > "${MANIFEST}"
echo -e "${GREEN}Manifest written: ${MANIFEST}${NC}"

# ── Stream logs in parallel ───────────────────────────────────────────────────
# Use `limactl shell ... -- docker logs --follow` directly.
# `orchestrate server logs` calls `docker logs` against the *active* Docker
# context, which may be "default" (host socket) rather than the Lima VM socket.
# Routing through limactl shell guarantees we reach the correct daemon regardless
# of which Docker context is currently active on the host.
print_header "Streaming logs in parallel — press Ctrl-C to stop"
echo ""

PIDS=()

for CONTAINER in "${CONTAINERS[@]}"; do
  LOG_FILE="${LOG_SESSION_DIR}/${CONTAINER}.log"
  echo -e "${GREEN}[START]${NC} ${CYAN}${CONTAINER}${NC} → ${LOG_FILE}"

  # Run limactl in a subshell so its PID is what we record.
  # `tee` writes to the log file AND stdout; `sed` prefixes each terminal line.
  # We capture the subshell PID ($!) which encompasses the whole pipeline.
  ( "${LIMACTL}" shell "${LIMA_VM}" -- docker logs --follow "${CONTAINER}" 2>&1 \
      | tee "${LOG_FILE}" \
      | sed "s/^/[${CONTAINER}] /" ) &

  PIDS+=($!)
done

echo ""
echo -e "${YELLOW}All streams started. Log lines appear below prefixed with [container-name].${NC}"
echo -e "${YELLOW}Press Ctrl-C to stop all streams and finalise the session.${NC}"
echo ""

# ── Trap Ctrl-C / SIGTERM ─────────────────────────────────────────────────────
# Function is defined BEFORE trap so the name is already resolved at trap time.
_inspector_stop() {
  # Block re-entry: a second Ctrl-C during cleanup is ignored.
  trap '' INT TERM

  echo -e "\n${YELLOW}Stopping all log streams...${NC}"
  kill "${PIDS[@]}" 2>/dev/null
  wait "${PIDS[@]}" 2>/dev/null

  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${YELLOW} Session summary ${NC}"
  for CONTAINER in "${CONTAINERS[@]}"; do
    LOG_FILE="${LOG_SESSION_DIR}/${CONTAINER}.log"
    if [ -f "${LOG_FILE}" ]; then
      LINES=$(wc -l < "${LOG_FILE}" | awk '{print $1}')
      echo -e "  ${CYAN}${CONTAINER}${NC}: ${LINES} lines → ${LOG_FILE}"
    fi
  done
  echo -e "${BLUE}========================================${NC}"
  echo -e "${GREEN}Session directory: ${LOG_SESSION_DIR}${NC}"
  echo -e "${GREEN}Manifest:          ${MANIFEST}${NC}"
  echo -e "${GREEN}To analyze:        bash wxo_server_log_analyze.sh${NC}"
  exit 0
}

trap '_inspector_stop' INT TERM

# ── Heartbeat: print line-count progress every 5 seconds ─────────────────────
# sleep runs as a background job; wait is interruptible by SIGINT.
# When Ctrl-C fires: wait returns non-zero → break exits the loop cleanly
# → the trap fires _inspector_stop exactly once.
TICK=0
while true; do
  sleep 5 &
  SLEEP_PID=$!
  wait ${SLEEP_PID}
  [ $? -ne 0 ] && break
  TICK=$(( TICK + 5 ))
  STATUS=""
  for CONTAINER in "${CONTAINERS[@]}"; do
    LOG_FILE="${LOG_SESSION_DIR}/${CONTAINER}.log"
    if [ -f "${LOG_FILE}" ]; then
      LINES=$(wc -l < "${LOG_FILE}" | awk '{print $1}')
      STATUS="${STATUS}  ${CONTAINER}:${LINES}"
    fi
  done
  echo -e "${BLUE}[${TICK}s]${NC}${STATUS}"
done
