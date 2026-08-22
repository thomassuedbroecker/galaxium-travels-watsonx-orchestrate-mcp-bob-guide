#!/usr/bin/env bash
# wxo_server_log_analyze.sh
# Analyze captured log files produced by wxo_server_log_inspector.sh.
# Produces a Sessions Overview: error counts, warning counts, top patterns,
# and a Markdown summary report ready for agent tool consumption.
#
# Usage:
#   ./wxo_server_log_analyze.sh [--log-dir <dir>] [--session <YYYYMMDD_HHMMSS>]
#                               [--report <file>] [--tail <n>]
#
# Options:
#   --log-dir   -d   Root directory that contains timestamped session folders.
#                    Defaults to ./server-logs
#   --session   -s   Specific session timestamp folder to analyze.
#                    Defaults to the most-recent session.
#   --report    -r   Path for the Markdown report.
#                    Defaults to <session-dir>/ANALYSIS_REPORT.md
#   --tail      -t   Number of tail lines to include per container.  Default 50.
#   --help           Show this message and exit.

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
LOG_DIR="./server-logs"
SESSION=""
REPORT_FILE=""
TAIL_LINES=50

# ── Argument parsing ──────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --log-dir|-d)   LOG_DIR="$2";       shift 2 ;;
    --session|-s)   SESSION="$2";       shift 2 ;;
    --report|-r)    REPORT_FILE="$2";   shift 2 ;;
    --tail|-t)      TAIL_LINES="$2";    shift 2 ;;
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

print_config() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${YELLOW} Tail lines: ${TAIL_LINES} ${NC}"
  echo -e "${YELLOW} Log dirctory: ${LOG_DIR} ${NC}"
  echo -e "${YELLOW} Target name: ${SESSION} ${NC}"
  echo -e "${YELLOW} Report file: ${REPORT_FILE} ${NC}"
}

hr() { echo "---"; }

# Read newline-separated input into a plain indexed array (bash 3.2 safe).
# Usage: read_into_array VARNAME "multiline string"
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

# ── Resolve session directory ─────────────────────────────────────────────────
print_header "Resolving session"

if [ -z "${SESSION}" ]; then
  SESSION=$(ls -1 "${LOG_DIR}" 2>/dev/null \
    | grep -E '^[0-9]{8}_[0-9]{6}$' | sort | tail -1)
  if [ -z "${SESSION}" ]; then
    echo -e "${RED}No session directories found in ${LOG_DIR}${NC}"
    echo -e "${YELLOW}Run wxo_server_log_inspector.sh first to capture logs.${NC}"
    exit 1
  fi
  echo -e "${CYAN}Auto-selected most recent session: ${SESSION}${NC}"
fi

SESSION_DIR="${LOG_DIR}/${SESSION}"

if [ ! -d "${SESSION_DIR}" ]; then
  echo -e "${RED}Session directory not found: ${SESSION_DIR}${NC}"
  exit 1
fi

# ── Load container list ───────────────────────────────────────────────────────
MANIFEST="${SESSION_DIR}/manifest.json"
ENV_FILE_META="(unknown)"

if [ -f "${MANIFEST}" ] && command -v jq >/dev/null 2>&1; then
  read_into_array CONTAINERS "$(jq -r '.containers[]' "${MANIFEST}")"
  ENV_FILE_META=$(jq -r '.env_file' "${MANIFEST}")
  # Build LOG_FILES array as session-dir + filename from manifest.
  LOG_FILES=()
  _i=0
  while IFS= read -r _fname; do
    [ -z "$_fname" ] && continue
    LOG_FILES[$_i]="${SESSION_DIR}/${_fname}"
    _i=$(( _i + 1 ))
  done < <(jq -r '.log_files[]' "${MANIFEST}")
else
  # Fallback: discover *.log files directly.
  LOG_FILES=()
  CONTAINERS=()
  _i=0
  for _f in "${SESSION_DIR}"/*.log; do
    [ -f "$_f" ] || continue
    LOG_FILES[$_i]="$_f"
    CONTAINERS[$_i]=$(basename "${_f}" .log)
    _i=$(( _i + 1 ))
  done
fi

echo -e "${GREEN}Session:    ${SESSION}${NC}"
echo -e "${GREEN}Directory:  ${SESSION_DIR}${NC}"
echo -e "${GREEN}Containers: ${#CONTAINERS[@]}${NC}"

if [ ${#LOG_FILES[@]} -eq 0 ]; then
  echo -e "${RED}No .log files found in ${SESSION_DIR}${NC}"
  exit 1
fi

# ── Set report path ───────────────────────────────────────────────────────────
[ -z "${REPORT_FILE}" ] && REPORT_FILE="${SESSION_DIR}/ANALYSIS_REPORT.md"

# ── Analysis functions ────────────────────────────────────────────────────────
# Each function receives a file path as $1.

# grep -c prints a count (including "0") but exits 1 on no-match.
# || true silences the non-zero exit while preserving the count on stdout.
count_errors()   { grep -ciE 'error|exception|fatal|panic|critical' "$1" 2>/dev/null || true; }
count_warnings() { grep -ciE 'warn(ing)?|deprecated'                "$1" 2>/dev/null || true; }
count_sessions() { grep -ciE 'session|thread_id'                    "$1" 2>/dev/null || true; }
count_lines()    { wc -l < "$1" | awk '{print $1}'; }

extract_errors()   { grep -iE 'error|exception|fatal|panic|traceback|critical' "$1" 2>/dev/null; }
extract_warnings() { grep -iE 'warn(ing)?|deprecated'                          "$1" 2>/dev/null; }
extract_sessions() { grep -iE 'session|thread_id|conversation|chat'            "$1" 2>/dev/null; }

top_patterns() {   # top_patterns <file> <n>
  grep -oE '\b[A-Z][A-Z_]{3,}\b' "$1" \
    | sort | uniq -c | sort -rn | head -"${2:-10}" 2>/dev/null
}

# ── Collect per-container metrics into parallel indexed arrays ────────────────
# CONTAINERS[] and LOG_FILES[] are already populated.
# We build: ERRCNT[], WARNCNT[], LINECNT[], SESSCNT[] at the same indices.
ERRCNT=()
WARNCNT=()
LINECNT=()
SESSCNT=()
TOTAL_ERRORS=0
TOTAL_WARNINGS=0

for i in "${!CONTAINERS[@]}"; do
  FILE="${LOG_FILES[$i]}"
  if [ ! -f "${FILE}" ]; then
    ERRCNT[$i]=0; WARNCNT[$i]=0; LINECNT[$i]=0; SESSCNT[$i]=0
    continue
  fi
  ERRCNT[$i]=$(count_errors   "${FILE}")
  WARNCNT[$i]=$(count_warnings "${FILE}")
  LINECNT[$i]=$(count_lines    "${FILE}")
  SESSCNT[$i]=$(count_sessions "${FILE}")
  TOTAL_ERRORS=$(( TOTAL_ERRORS   + ERRCNT[$i] ))
  TOTAL_WARNINGS=$(( TOTAL_WARNINGS + WARNCNT[$i] ))
done

# ── Terminal Sessions Overview ────────────────────────────────────────────────
print_header "Sessions Overview"

printf "\n%-40s %8s %8s %8s %10s\n" "Container" "Lines" "Errors" "Warnings" "Sessions"
printf "%-40s %8s %8s %8s %10s\n" \
  "$(printf '%0.s-' $(seq 1 40))" "--------" "--------" "--------" "----------"

for i in "${!CONTAINERS[@]}"; do
  CONT="${CONTAINERS[$i]}"
  COLOR="${GREEN}"
  [ "${ERRCNT[$i]}" -gt 0 ] && COLOR="${RED}"
  [ "${WARNCNT[$i]}" -gt 0 ] && [ "${ERRCNT[$i]}" -eq 0 ] && COLOR="${YELLOW}"
  printf "${COLOR}%-40s %8s %8s %8s %10s${NC}\n" \
    "${CONT}" "${LINECNT[$i]}" "${ERRCNT[$i]}" "${WARNCNT[$i]}" "${SESSCNT[$i]}"
done
printf "\n%-40s %8s %8s %8s\n" "TOTAL" "" "${TOTAL_ERRORS}" "${TOTAL_WARNINGS}"

# ── Per-container terminal detail ─────────────────────────────────────────────
for i in "${!CONTAINERS[@]}"; do
  CONT="${CONTAINERS[$i]}"
  FILE="${LOG_FILES[$i]}"
  [ ! -f "${FILE}" ] && continue

  print_header "Detail: ${CONT}"

  if [ "${ERRCNT[$i]}" -gt 0 ]; then
    echo -e "${RED}── Errors ──${NC}"
    extract_errors "${FILE}" | head -20
  else
    echo -e "${GREEN}No errors found.${NC}"
  fi

  if [ "${WARNCNT[$i]}" -gt 0 ]; then
    echo -e "${YELLOW}── Warnings ──${NC}"
    extract_warnings "${FILE}" | head -10
  fi

  echo -e "${CYAN}── Top log-level tokens ──${NC}"
  top_patterns "${FILE}" 8

  echo -e "${CYAN}── Tail (last ${TAIL_LINES} lines) ──${NC}"
  tail -"${TAIL_LINES}" "${FILE}"
done

# ── Markdown Report ───────────────────────────────────────────────────────────
print_header "Writing Markdown report → ${REPORT_FILE}"

{
  echo "# watsonx Orchestrate Server Log Analysis"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| Session | \`${SESSION}\` |"
  echo "| Generated | $(date '+%Y-%m-%d %H:%M:%S') |"
  echo "| Log directory | \`${SESSION_DIR}\` |"
  echo "| Env file | \`${ENV_FILE_META}\` |"
  echo "| Total errors | **${TOTAL_ERRORS}** |"
  echo "| Total warnings | **${TOTAL_WARNINGS}** |"
  echo ""
  hr

  echo ""
  echo "## Sessions Overview"
  echo ""
  echo "| Container | Lines | Errors | Warnings | Session Refs |"
  echo "|-----------|------:|-------:|---------:|-------------:|"
  for i in "${!CONTAINERS[@]}"; do
    echo "| \`${CONTAINERS[$i]}\` | ${LINECNT[$i]} | ${ERRCNT[$i]} | ${WARNCNT[$i]} | ${SESSCNT[$i]} |"
  done
  echo ""
  hr

  for i in "${!CONTAINERS[@]}"; do
    CONT="${CONTAINERS[$i]}"
    FILE="${LOG_FILES[$i]}"
    echo ""
    echo "## Container: \`${CONT}\`"
    echo ""
    echo "**Log file:** \`${FILE}\`"
    echo ""

    if [ ! -f "${FILE}" ]; then
      echo "_Log file not found._"
      hr
      continue
    fi

    echo "### Errors (${ERRCNT[$i]})"
    if [ "${ERRCNT[$i]}" -gt 0 ]; then
      echo '```'
      extract_errors "${FILE}" | head -30
      echo '```'
    else
      echo "_No errors detected._"
    fi
    echo ""

    echo "### Warnings (${WARNCNT[$i]})"
    if [ "${WARNCNT[$i]}" -gt 0 ]; then
      echo '```'
      extract_warnings "${FILE}" | head -15
      echo '```'
    else
      echo "_No warnings detected._"
    fi
    echo ""

    echo "### Session / Thread References (${SESSCNT[$i]})"
    SESS_LINES=$(extract_sessions "${FILE}" | head -20)
    if [ -n "${SESS_LINES}" ]; then
      echo '```'
      echo "${SESS_LINES}"
      echo '```'
    else
      echo "_No session or thread_id references found._"
    fi
    echo ""

    echo "### Top Log-Level Tokens"
    echo '```'
    top_patterns "${FILE}" 10
    echo '```'
    echo ""

    echo "### Tail (last ${TAIL_LINES} lines)"
    echo '```'
    tail -"${TAIL_LINES}" "${FILE}"
    echo '```'
    hr
  done

  echo ""
  echo "---"
  echo "_Report generated by \`wxo_server_log_analyze.sh\` — session \`${SESSION}\`_"
} > "${REPORT_FILE}"

echo -e "${GREEN}Report written: ${REPORT_FILE}${NC}"

# ── Exit status ───────────────────────────────────────────────────────────────
if [ "${TOTAL_ERRORS}" -gt 0 ]; then
  echo -e "${RED}${BOLD}Analysis complete — ${TOTAL_ERRORS} error(s) found across all containers.${NC}"
  exit 2
elif [ "${TOTAL_WARNINGS}" -gt 0 ]; then
  echo -e "${YELLOW}${BOLD}Analysis complete — ${TOTAL_WARNINGS} warning(s) found, no errors.${NC}"
  exit 1
else
  echo -e "${GREEN}${BOLD}Analysis complete — logs are clean.${NC}"
  exit 0
fi
