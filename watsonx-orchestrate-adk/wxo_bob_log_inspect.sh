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

# ── Load environment variables first so every subsequent command inherits them ─
if [ -f ".env" ]; then
  set -a; source ".env"; set +a
fi

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
require_cmd bob    "Install IBM Bob CLI: npm install -g @ibm/bob-cli"
require_cmd jq     "Install jq: brew install jq"
require_cmd python3 "Python 3 is required to locate the bundled limactl"

# ── Activate venv ─────────────────────────────────────────────────────────────
if [ -f ".venv/bin/activate" ]; then
  source .venv/bin/activate
fi

# ── Step 1: Optional log capture ──────────────────────────────────────────────
# Timed capture strategy: sleep first, then pull logs with --since <start_time>.
#
# WHY NOT docker logs --follow:
#   limactl shell opens an SSH tunnel into the Lima VM.  Killing the local
#   limactl/subshell process closes the SSH client but docker logs --follow
#   keeps running inside the VM; its stdout holds the pipe open so tee/sed
#   on the host never receive EOF and block forever — wait never returns.
#   No amount of PID or PGID killing on the host side can reach the process
#   inside the VM.
#
# WHY --since works:
#   docker logs --since <timestamp> --until <timestamp> is a bounded, blocking
#   call: it fetches the log slice and exits.  No background jobs, no killing,
#   no hanging pipes.  We record CAPTURE_START before the sleep, sleep for the
#   requested duration, then call docker logs once per container.  The call
#   finishes on its own in a few seconds.
if [ "${DO_CAPTURE}" = "true" ]; then
  print_header "Step 1 — Capturing logs for ${CAPTURE_SECONDS}s"

  # ── Locate bundled limactl ──────────────────────────────────────────────────
  LIMACTL=$(python3 -c "
from importlib.resources import files
p = files('ibm_watsonx_orchestrate.developer_edition.resources.lima.bin') / 'limactl'
print(str(p))
" 2>/dev/null)

  if [ -z "${LIMACTL}" ] || [ ! -f "${LIMACTL}" ]; then
    echo -e "${RED}ERROR: bundled limactl not found.${NC}" >&2
    echo -e "${RED}Is the virtual environment activated and ibm-watsonx-orchestrate installed?${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}limactl: ${LIMACTL}${NC}"

  # ── Discover containers ─────────────────────────────────────────────────────
  LIMA_VM="ibm-watsonx-orchestrate"
  CAPTURE_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
  CAPTURE_SESSION_DIR="${LOG_DIR}/${CAPTURE_TIMESTAMP}"

  RAW_CONTAINERS=$("${LIMACTL}" shell "${LIMA_VM}" -- \
    docker ps --format '{{.Names}}' 2>/dev/null)
  if [ -z "${RAW_CONTAINERS}" ]; then
    echo -e "${RED}ERROR: no running containers found inside the Lima VM.${NC}" >&2
    echo -e "${YELLOW}Start the server with: bash wxo_local_start.sh${NC}" >&2
    exit 1
  fi

  mkdir -p "${CAPTURE_SESSION_DIR}"

  # ── Fetch a full log snapshot per container (blocking, exits cleanly) ────────
  # docker logs (no --follow) reads all buffered output and exits immediately.
  # No background jobs, no killing, no hanging pipes — guaranteed to terminate.
  # We sleep first so that any activity during the capture window is included,
  # then pull the full log buffer which covers the whole server lifetime.
  echo -e "${CYAN}Waiting ${CAPTURE_SECONDS}s then fetching logs...${NC}"
  sleep "${CAPTURE_SECONDS}"
  echo ""

  LOG_FILES_LIST=()
  while IFS= read -r CONTAINER; do
    [ -z "${CONTAINER}" ] && continue
    LOG_FILE="${CAPTURE_SESSION_DIR}/${CONTAINER}.log"
    echo -e "${GREEN}[FETCH]${NC} ${CYAN}${CONTAINER}${NC} → ${LOG_FILE}"
    # < /dev/null prevents limactl/docker from consuming the loop's stdin herestring.
    "${LIMACTL}" shell "${LIMA_VM}" -- \
      docker logs "${CONTAINER}" < /dev/null > "${LOG_FILE}" 2>&1
    LINES=$(wc -l < "${LOG_FILE}" | tr -d ' ')
    echo -e "        ${LINES} lines"
    LOG_FILES_LIST+=("${CONTAINER}.log")
  done <<< "${RAW_CONTAINERS}"

  # ── Write manifest (matches format expected by wxo_server_log_analyze.sh) ───
  {
    echo "{"
    echo "  \"timestamp\": \"${CAPTURE_TIMESTAMP}\","
    echo "  \"env_file\": \"${ENV_FILE}\","
    LAST_IDX=$(( ${#LOG_FILES_LIST[@]} - 1 ))
    echo "  \"containers\": ["
    for i in "${!LOG_FILES_LIST[@]}"; do
      COMMA=","; [ $i -eq $LAST_IDX ] && COMMA=""
      # strip .log suffix for container name
      CNAME="${LOG_FILES_LIST[$i]%.log}"
      echo "    \"${CNAME}\"${COMMA}"
    done
    echo "  ],"
    echo "  \"log_files\": ["
    for i in "${!LOG_FILES_LIST[@]}"; do
      COMMA=","; [ $i -eq $LAST_IDX ] && COMMA=""
      echo "    \"${LOG_FILES_LIST[$i]}\"${COMMA}"
    done
    echo "  ]"
    echo "}"
  } > "${CAPTURE_SESSION_DIR}/manifest.json"

  echo -e "${GREEN}Capture complete → ${CAPTURE_SESSION_DIR}${NC}"

  # Force the session resolver below to use this new session.
  SESSION="${CAPTURE_TIMESTAMP}"
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

BOB_START=$(date +%s)
bob run \
  --mode "${BOB_MODE}" \
  --accept-license \
  "${FULL_PROMPT}" | tee -a "${EXPORT_FILE}"
BOB_END=$(date +%s)
BOB_ELAPSED=$(( BOB_END - BOB_START ))

# ── Step 4b: Clean the exported file ─────────────────────────────────────────
python3 - "${EXPORT_FILE}" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    raw = f.read()

# ── 1. Remove <thinking> blocks ───────────────────────────────────────────────
clean = re.sub(r'<thinking>.*?</thinking>\n?', '', raw, flags=re.DOTALL)

# ── 2. Remove [using tool …] lines and ---output--- fences ────────────────────
clean = re.sub(r'\[using tool [^\]]+\]\n?', '', clean)
clean = re.sub(r'---output---\n?', '', clean)

# ── 3. Strip Bob's conversation-frame wrapper lines ───────────────────────────
clean = re.sub(r'^[─\-]{10,}\n', '', clean, flags=re.MULTILINE)
clean = re.sub(r'^(?:User|Assistant)\s*\(\d+\)[^\n]*\n', '', clean, flags=re.MULTILINE)

# ── 4. Strip trailing whitespace on every line (terminal padding) ─────────────
clean = re.sub(r'[ \t]+$', '', clean, flags=re.MULTILINE)

# ── 5. Convert Unicode box-drawing tables to GFM pipe tables ──────────────────
BOX_CHARS = '┌┬┐├┼┤└┴┘─'

def is_box_border(line):
    stripped = line.strip()
    return bool(stripped) and all(c in BOX_CHARS for c in stripped)

def box_row_to_gfm(line):
    parts = line.split('│')
    cells = [p.strip() for p in parts[1:-1]]
    return '| ' + ' | '.join(cells) + ' |'

lines = clean.splitlines()
out = []
i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()

    if is_box_border(stripped):
        i += 1
        continue

    if stripped.startswith('│'):
        raw_rows = []
        while i < len(lines) and (lines[i].strip().startswith('│') or is_box_border(lines[i].strip())):
            if not is_box_border(lines[i].strip()):
                raw_rows.append(lines[i])
            i += 1
        def col_count_of(row):
            return len(row.split('│')) - 2
        if raw_rows and all(col_count_of(r) == 1 for r in raw_rows):
            for r in raw_rows:
                cell = r.split('│')[1].strip()
                if cell:
                    out.append('> ' + cell)
        else:
            table_rows = [box_row_to_gfm(r) for r in raw_rows]
            if len(table_rows) >= 2:
                n_cols = table_rows[0].count('|') - 1
                separator = '|' + '---|' * n_cols
                table_rows.insert(1, separator)
            out.extend(table_rows)
        continue

    out.append(line)
    i += 1

clean = '\n'.join(out)

# ── 6. Convert ────… horizontal rules to Markdown --- ────────────────────────
clean = re.sub(r'^[─]{4,}\s*$', '---', clean, flags=re.MULTILINE)

# ── 7. Promote bare section titles to ### headings ────────────────────────────
def promote_bare_headings(text):
    result = []
    lines = text.splitlines()
    n = len(lines)
    for idx, line in enumerate(lines):
        prev_blank = (idx == 0) or (lines[idx-1].strip() == '')
        next_blank = (idx == n-1) or (lines[idx+1].strip() == '')
        s = line.strip()
        is_candidate = (
            s
            and not line.startswith('#')
            and not line.startswith('|')
            and not line.startswith('-')
            and not line.startswith('*')
            and not line.startswith('`')
            and not line.startswith('>')
            and not line.startswith('  ')
            and prev_blank
            and next_blank
            and not s.endswith('.')
            and not s.endswith(',')
            and not s.endswith(':')
            and s not in ('---', '–––', '===')
            and any(c.isalpha() for c in s)
            and len(s) <= 60
        )
        if is_candidate:
            result.append('### ' + s)
        else:
            result.append(line)
    return '\n'.join(result)

clean = promote_bare_headings(clean)

# ── 8. Remove echoed prompt context block before Bob's answer ────────────────
clean = re.sub(
    r'(---\n)\n.*?(?=(?:###\s*1\.|# watsonx Orchestrate Server Log Analysis Report))',
    r'\1\n',
    clean,
    count=1,
    flags=re.DOTALL,
)

# ── 9. De-duplicate repeated report body ─────────────────────────────────────
marker = '# watsonx Orchestrate Server Log Analysis Report'
parts = clean.split(marker)
if len(parts) > 2:
    clean = parts[0].rstrip() + '\n\n' + marker + parts[-1]

# ── 10. Collapse runs of 3+ blank lines to 2 ─────────────────────────────────
clean = re.sub(r'\n{3,}', '\n\n', clean)

with open(sys.argv[1], 'w') as f:
    f.write(clean.strip() + '\n')

print(f"Cleaned: {sys.argv[1]}")
PYEOF

# ── Append Bob CLI cost section ────────────────────────────────────────────────
cat >> "${EXPORT_FILE}" <<COST_SECTION

---

## IBM Bob CLI Usage

| Field | Value |
|---|---|
| Bob mode | ${BOB_MODE} |
| Bob CLI wall-clock time | ${BOB_ELAPSED} s |
| Prompt size (chars) | $(echo -n "${FULL_PROMPT}" | wc -c | tr -d ' ') |
| Note | Token cost depends on the LLM backing the Bob CLI. Set \`BOB_API_KEY\` to your IBM Cloud API key. Monitor actual token spend in your IBM Cloud account under the watsonx model you configured. |

COST_SECTION

# ── Footer ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}Session:      ${SESSION}${NC}"
echo -e "${GREEN}Report:       ${REPORT_FILE}${NC}"
echo -e "${GREEN}Bob mode:     ${BOB_MODE}${NC}"
echo -e "${GREEN}Bob time:     ${BOB_ELAPSED} s${NC}"
echo -e "${GREEN}Bob analysis: ${EXPORT_FILE}${NC}"
