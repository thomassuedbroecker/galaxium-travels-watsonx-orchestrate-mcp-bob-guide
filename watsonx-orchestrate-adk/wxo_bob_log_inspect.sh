#!/usr/bin/env bash
# wxo_bob_log_inspect.sh
# Automated watsonx Orchestrate server-log inspection driven entirely from the
# terminal using the IBM Bob CLI.
#
# Pipeline:
#   1. Resolve / optionally run wxo_server_log_inspector.sh  (log capture)
#   2. Run wxo_server_log_analyze.sh                          (pre-analysis)
#   3. Build a combined prompt and pass it to: bob run --mode <mode> "<prompt>"
#   4. Export Bob's response to BOB_ANALYSIS_REPORT.md        (markdown export)
#
# Usage:
#   bash wxo_bob_log_inspect.sh [OPTIONS]
#
# Options:
#   --capture            Run wxo_server_log_inspector.sh first for <seconds> then
#                        stop it automatically. Requires --capture-seconds.
#   --capture-seconds N  How many seconds to capture logs before stopping.
#                        Default: 30. Only used with --capture.
#   --session   -s       Specific session timestamp (YYYYMMDD_HHMMSS) to analyse.
#                        Defaults to the most-recent session in --log-dir.
#   --log-dir   -d       Root directory of session folders. Default: ./server-logs
#   --question  -q       Question for Bob. Default: standard health question.
#   --mode      -m       Bob run mode. Default: ask
#   --export-file -o     Path for the exported Bob analysis markdown.
#                        Default: <session-dir>/BOB_ANALYSIS_REPORT.md
#   --env-file  -e       Path to a .env file. Default: .env
#   --full-report        Send the complete ANALYSIS_REPORT.md to Bob instead of
#                        the summary extract. Slower but gives Bob full log detail.
#   --help               Show this message and exit.
#
# Examples:
#   # Analyse the most-recent session and ask Bob about health:
#   bash wxo_bob_log_inspect.sh
#
#   # Capture 60 s of logs, then analyse and ask Bob:
#   bash wxo_bob_log_inspect.sh --capture --capture-seconds 60
#
#   # Custom question:
#   bash wxo_bob_log_inspect.sh -q "Which containers had Redis connection errors?"
#
#   # Use arch-review mode for a deeper analysis:
#   bash wxo_bob_log_inspect.sh --mode arch-review
#
#   # Write Bob's response to a specific file:
#   bash wxo_bob_log_inspect.sh -o ./my-report.md

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
DO_CAPTURE=false
CAPTURE_SECONDS=30
LOG_DIR="./server-logs"
SESSION=""
BOB_MODE="ask"
ENV_FILE=".env"
EXPORT_FILE=""
QUESTION="Analyse the watsonx Orchestrate server log report below. Provide: 1) Overall health status. 2) Sessions Overview table. 3) Top 5 containers by error count. 4) Root cause notes per error container — which are Developer Edition startup noise versus real issues. 5) Recommendation."

# ── Argument parsing ──────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --capture)              DO_CAPTURE=true;          shift ;;
    --capture-seconds)      CAPTURE_SECONDS="$2";     shift 2 ;;
    --session|-s)           SESSION="$2";             shift 2 ;;
    --log-dir|-d)           LOG_DIR="$2";             shift 2 ;;
    --question|-q)          QUESTION="$2";            shift 2 ;;
    --mode|-m)              BOB_MODE="$2";            shift 2 ;;
    --export-file|-o)       EXPORT_FILE="$2";         shift 2 ;;
    --env-file|-e)          ENV_FILE="$2";            shift 2 ;;
    --full-report)          USE_FULL_REPORT=true;     shift ;;
    --help)
      sed -n -e '/^#!/d' -e '/^#/!q' -e 's/^# \{0,2\}//p' "$0"
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
print_header() {
  echo -e "\n${BLUE}════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  $* ${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: '$1' not found. $2${NC}" >&2; exit 1
  }
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
require_cmd bob  "Install IBM Bob CLI: npm install -g @ibm/bob-cli"
require_cmd jq   "Install jq: brew install jq"

# ── Activate venv ─────────────────────────────────────────────────────────────
if [ -f ".venv/bin/activate" ]; then
  source .venv/bin/activate
fi

if [ -f "${ENV_FILE}" ]; then
  set -a; source "${ENV_FILE}"; set +a
fi

# ── Step 1: Optional log capture ──────────────────────────────────────────────
if [ "${DO_CAPTURE}" = "true" ]; then
  print_header "Step 1 — Capturing logs for ${CAPTURE_SECONDS}s"
  echo -e "${CYAN}Starting wxo_server_log_inspector.sh in background...${NC}"

  bash wxo_server_log_inspector.sh &
  INSPECTOR_PID=$!

  echo -e "${CYAN}Capturing... (${CAPTURE_SECONDS}s)${NC}"
  sleep "${CAPTURE_SECONDS}"

  echo -e "${YELLOW}Stopping capture (PID ${INSPECTOR_PID})...${NC}"
  kill "${INSPECTOR_PID}" 2>/dev/null
  wait "${INSPECTOR_PID}" 2>/dev/null
  echo -e "${GREEN}Capture complete.${NC}"
else
  print_header "Step 1 — Log capture"
  echo -e "${CYAN}Skipping capture. Using existing session.${NC}"
  echo -e "${CYAN}(Pass --capture --capture-seconds N to capture fresh logs first.)${NC}"
fi

# ── Step 2: Resolve session ───────────────────────────────────────────────────
print_header "Step 2 — Resolving session"

if [ -z "${SESSION}" ]; then
  SESSION=$(ls -1 "${LOG_DIR}" 2>/dev/null \
    | grep -E '^[0-9]{8}_[0-9]{6}$' | sort | tail -1)
fi

if [ -z "${SESSION}" ]; then
  echo -e "${RED}No sessions found in ${LOG_DIR}.${NC}"
  echo -e "${YELLOW}Run:  bash wxo_server_log_inspector.sh${NC}"
  echo -e "${YELLOW}  or: bash wxo_bob_log_inspect.sh --capture --capture-seconds 30${NC}"
  exit 1
fi

SESSION_DIR="${LOG_DIR}/${SESSION}"
echo -e "${GREEN}Session:   ${SESSION}${NC}"
echo -e "${GREEN}Directory: ${SESSION_DIR}${NC}"

# ── Step 3: Run the analyser (pre-analysis) ───────────────────────────────────
print_header "Step 3 — Pre-analysis (wxo_server_log_analyze.sh)"

REPORT_FILE="${SESSION_DIR}/ANALYSIS_REPORT.md"

bash wxo_server_log_analyze.sh \
  --log-dir "${LOG_DIR}" \
  --session "${SESSION}" \
  --report  "${REPORT_FILE}" \
  --tail    20

echo -e "\n${GREEN}Report written: ${REPORT_FILE}${NC}"

# ── Step 3b: Extract summary section only (fast) ─────────────────────────────
# The full ANALYSIS_REPORT.md contains 1500+ lines of raw log excerpts.
# Feeding all of it to Bob costs tokens and causes slow responses.
# We extract only the header metadata + Sessions Overview table (≈40 lines)
# which is all the LLM needs to answer health/overview questions.
# Use --full-report to send the complete file instead.
SUMMARY_FILE="${SESSION_DIR}/SUMMARY_BY_BOB.md"

python3 - "${REPORT_FILE}" "${SUMMARY_FILE}" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
# Keep: metadata table + Sessions Overview table (everything up to first --- after the table)
m = re.search(r'^(.*?## Sessions Overview.*?^---)', content, re.DOTALL | re.MULTILINE)
excerpt = m.group(1) if m else content[:3000]
with open(sys.argv[2], 'w') as f:
    f.write(excerpt)
    f.write('\n\n_Full report: ' + sys.argv[1] + '_\n')
print(f"Summary: {len(excerpt.splitlines())} lines  ({len(excerpt)} chars)")
PYEOF

CONTEXT_FILE="${SUMMARY_FILE}"
if [ "${USE_FULL_REPORT:-false}" = "true" ]; then
  CONTEXT_FILE="${REPORT_FILE}"
  echo -e "${YELLOW}Using full report (${CONTEXT_FILE}).${NC}"
else
  echo -e "${GREEN}Using summary extract (${CONTEXT_FILE}) — pass --full-report for full detail.${NC}"
fi

# ── Step 4: Invoke Bob CLI with the summary as stdin ─────────────────────────
print_header "Step 4 — IBM Bob CLI analysis (mode: ${BOB_MODE})"

# Resolve the export file path now that SESSION_DIR is known.
if [ -z "${EXPORT_FILE}" ]; then
  EXPORT_FILE="${SESSION_DIR}/BOB_ANALYSIS_REPORT.md"
fi

# Write a metadata header to the export file before streaming Bob's response.
# Use a distinct heading (## Run Metadata) so it does not collide with Bob's
# own "# watsonx Orchestrate Server Log Analysis Report" heading when the
# post-processing step de-duplicates that title.
RUN_TS=$(date '+%Y-%m-%d %H:%M:%S')
CONTEXT_LABEL="${CONTEXT_FILE##*/}"
cat > "${EXPORT_FILE}" <<HEADER
## Run Metadata

| Field | Value |
|---|---|
| Session | ${SESSION} |
| Bob mode | ${BOB_MODE} |
| Context file | ${CONTEXT_LABEL} |
| Generated | ${RUN_TS} |

---

HEADER

echo -e "${CYAN}Building prompt → bob run --mode \"${BOB_MODE}\" \"<context+question>\"${NC}"
echo -e "${CYAN}Output → terminal + ${EXPORT_FILE}${NC}"
echo ""

# Build a single prompt string: context file content + question.
# bob run takes the prompt as a positional argument and runs non-interactively.
CONTEXT_CONTENT=$(cat "${CONTEXT_FILE}")
FULL_PROMPT="${CONTEXT_CONTENT}

${QUESTION}"

bob run \
  --mode "${BOB_MODE}" \
  --accept-license \
  "${FULL_PROMPT}" | tee -a "${EXPORT_FILE}"

# ── Step 4b: Clean the exported file ─────────────────────────────────────────
# Bob's raw stdout contains <thinking> blocks, [using tool …] scaffolding, and
# ---output--- markers. When the analysis body is repeated (intermediate + final
# output), only the last occurrence is kept. Strip all noise in-place.
python3 - "${EXPORT_FILE}" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    raw = f.read()

# 1. Remove <thinking>…</thinking> blocks (including multiline)
clean = re.sub(r'<thinking>.*?</thinking>\n?', '', raw, flags=re.DOTALL)

# 2. Remove [using tool …] lines and the ---output--- fences around them
clean = re.sub(r'\[using tool [^\]]+\]\n?', '', clean)
clean = re.sub(r'---output---\n?', '', clean)

# 3. If the analysis heading appears more than once (duplicate from intermediate
#    + final output), keep only the content after the last occurrence.
marker = '# watsonx Orchestrate Server Log Analysis Report'
parts = clean.split(marker)
if len(parts) > 2:
    # re-attach: header block (parts[0]) + last analysis body
    clean = parts[0].rstrip() + '\n\n' + marker + parts[-1]

# 4. Collapse runs of 3+ blank lines to 2
clean = re.sub(r'\n{3,}', '\n\n', clean)

with open(sys.argv[1], 'w') as f:
    f.write(clean.strip() + '\n')

print(f"Cleaned export: {sys.argv[1]}")
PYEOF

# ── Footer ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}Session:      ${SESSION}${NC}"
echo -e "${GREEN}Report:       ${REPORT_FILE}${NC}"
echo -e "${GREEN}Bob mode:     ${BOB_MODE}${NC}"
echo -e "${GREEN}Bob analysis: ${EXPORT_FILE}${NC}"
