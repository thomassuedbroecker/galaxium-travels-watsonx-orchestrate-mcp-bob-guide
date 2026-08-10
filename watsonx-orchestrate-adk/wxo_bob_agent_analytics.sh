#!/usr/bin/env bash
# wxo_bob_agent_analytics.sh
# Run a test against a watsonx Orchestrate agent, export the Agent Analytics
# (observability trace from local Langfuse), and pipe the trace JSON to the
# IBM Bob CLI for structured analysis. The Bob report is saved as a Markdown file.
#
# Pipeline:
#   1. Send a test message via the runs API → captures run_id + trace_id
#   2. Poll until the run completes
#   3. Export trace observations from local Langfuse (http://localhost:3010)
#   4. bob run --mode ask "<context+question>"  → AI analysis
#   5. Save report to <output-dir>/BOB_AGENT_ANALYTICS_REPORT_<ts>.md
#
# Usage:
#   bash wxo_bob_agent_analytics.sh [OPTIONS]
#
# Options:
#   --agent      -n   Agent name (snake_case). Default: agent_hello_world
#   --message    -m   Test message to send. Default: "Hello, are you working?"
#   --output-dir -o   Directory for generated files. Default: ./agent-analytics
#   --question   -q   Question for Bob. Default: standard trace analysis question.
#   --bob-mode        Bob run mode. Default: ask
#   --export-file     Path for the Bob analysis markdown.
#                     Default: <output-dir>/BOB_AGENT_ANALYTICS_REPORT_<ts>.md
#   --env-file   -e   Path to a .env file. Default: .env
#   --langfuse-url    Langfuse API base URL. Default: http://localhost:3010
#   --langfuse-pk     Langfuse public key.  Default: pk-lf-orchestrate
#   --langfuse-sk     Langfuse secret key.  Default: sk-lf-orchestrate
#   --trace-only      Export trace only; skip the Bob analysis.
#   --help            Show this message and exit.
#
# Requirements:
#   - orchestrate CLI active (orchestrate env activate local)
#   - Langfuse running locally (Developer Edition started with --with-ibm-telemetry)
#   - jq
#   - bob CLI (npm install -g @ibm/bob-cli) — unless --trace-only is set
#   - The agent must be imported in the active environment.
#
# Examples:
#   # Run test + export trace + Bob analysis (defaults):
#   bash wxo_bob_agent_analytics.sh
#
#   # Custom agent and message:
#   bash wxo_bob_agent_analytics.sh -n my_agent -m "What can you do?"
#
#   # Export trace only, no Bob:
#   bash wxo_bob_agent_analytics.sh --trace-only
#
#   # Use arch-review mode for deeper analysis:
#   bash wxo_bob_agent_analytics.sh --bob-mode arch-review
#
#   # Write Bob's report to a specific file:
#   bash wxo_bob_agent_analytics.sh --export-file ./reports/analytics_$(date +%Y%m%d).md

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── Defaults ───────────────────────────────────────────────────────────────────
AGENT_NAME="agent_hello_world"
TEST_MESSAGE="Hello, are you working?"
OUTPUT_DIR="./agent-analytics"
ENV_FILE=".env"
BOB_MODE="ask"
EXPORT_FILE=""
TRACE_ONLY=false
LANGFUSE_URL="http://localhost:3010"
LANGFUSE_PK="pk-lf-orchestrate"
LANGFUSE_SK="sk-lf-orchestrate"
POLL_TIMEOUT=120
QUESTION="You are analysing a watsonx Orchestrate Agent Analytics (Langfuse observability) JSON export.
Provide a concise structured report with:
1. Run summary — agent name, trace ID, overall status, total duration.
2. Step-by-step trace — list each observation with type, name, duration, and status.
3. Tool calls detected — which tools were invoked and with what arguments.
4. Errors or anomalies — any failed steps or unexpected observations.
5. Recommendation — is the agent behaving as expected? Any issues to address?"

# ── Argument parsing ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --agent|-n)         AGENT_NAME="$2";    shift 2 ;;
    --message|-m)       TEST_MESSAGE="$2";  shift 2 ;;
    --output-dir|-o)    OUTPUT_DIR="$2";    shift 2 ;;
    --question|-q)      QUESTION="$2";      shift 2 ;;
    --bob-mode)         BOB_MODE="$2";      shift 2 ;;
    --export-file)      EXPORT_FILE="$2";   shift 2 ;;
    --env-file|-e)      ENV_FILE="$2";      shift 2 ;;
    --langfuse-url)     LANGFUSE_URL="$2";  shift 2 ;;
    --langfuse-pk)      LANGFUSE_PK="$2";   shift 2 ;;
    --langfuse-sk)      LANGFUSE_SK="$2";   shift 2 ;;
    --trace-only)       TRACE_ONLY=true;    shift ;;
    --help)
      sed -n -e '/^#!/d' -e '/^#/!q' -e 's/^# \{0,2\}//p' "$0"
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
  esac
done

# ── Helpers ────────────────────────────────────────────────────────────────────
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

# ── Pre-flight ─────────────────────────────────────────────────────────────────
require_cmd jq "Install jq: brew install jq"
require_cmd python3 "python3 is required"
if [ "${TRACE_ONLY}" = "false" ]; then
  require_cmd bob "Install IBM Bob CLI: npm install -g @ibm/bob-cli"
fi

# ── Activate venv ──────────────────────────────────────────────────────────────
if [ -f ".venv/bin/activate" ]; then
  # shellcheck source=/dev/null
  source .venv/bin/activate
fi

if [ -f "${ENV_FILE}" ]; then
  set -a; source "${ENV_FILE}"; set +a
fi

# ── Resolve WXO URL and auth token from orchestrate config ─────────────────────
CONFIG_FILE="${HOME}/.config/orchestrate/config.yaml"
CREDS_FILE="${HOME}/.cache/orchestrate/credentials.yaml"

[ -f "${CONFIG_FILE}" ] || { echo -e "${RED}ERROR: ${CONFIG_FILE} not found. Run: orchestrate env activate local${NC}" >&2; exit 1; }
[ -f "${CREDS_FILE}" ]  || { echo -e "${RED}ERROR: ${CREDS_FILE} not found. Run: orchestrate env activate local${NC}" >&2; exit 1; }

ACTIVE_ENV=$(python3 - "${CONFIG_FILE}" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f: c = f.read()
m = re.search(r'active_environment:\s*(\S+)', c)
print(m.group(1) if m else '')
PYEOF
)
[ -n "${ACTIVE_ENV}" ] || { echo -e "${RED}ERROR: No active environment. Run: orchestrate env activate local${NC}" >&2; exit 1; }

WXO_URL=$(python3 - "${CONFIG_FILE}" "${ACTIVE_ENV}" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f: c = f.read()
env = sys.argv[2]
# config.yaml: environments section has 2-space indented env keys, 4-space values
m = re.search(r'(?m)^  ' + re.escape(env) + r':\s*\n((?:    [^\n]+\n)*)', c)
if not m: sys.exit(1)
u = re.search(r'wxo_url:\s*(\S+)', m.group(1))
print(u.group(1).rstrip('/') if u else '')
PYEOF
)
[ -n "${WXO_URL}" ] || { echo -e "${RED}ERROR: No wxo_url for '${ACTIVE_ENV}'. Run: orchestrate env activate local${NC}" >&2; exit 1; }

TOKEN=$(python3 - "${CREDS_FILE}" "${ACTIVE_ENV}" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f: c = f.read()
env = sys.argv[2]
# credentials.yaml: auth section has 2-space indented env keys, 4-space values
m = re.search(r'(?m)^  ' + re.escape(env) + r':\s*\n((?:    [^\n]+\n)*)', c)
if not m: sys.exit(1)
t = re.search(r'wxo_mcsp_token:\s*(\S+)', m.group(1))
print(t.group(1) if t else '')
PYEOF
)
[ -n "${TOKEN}" ] || { echo -e "${RED}ERROR: No auth token for '${ACTIVE_ENV}'. Run: orchestrate env activate local${NC}" >&2; exit 1; }

echo -e "${CYAN}Environment : ${ACTIVE_ENV}${NC}"
echo -e "${CYAN}WXO URL     : ${WXO_URL}${NC}"
echo -e "${CYAN}Langfuse    : ${LANGFUSE_URL}${NC}"

# ── Verify Langfuse is reachable ───────────────────────────────────────────────
LF_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "${LANGFUSE_PK}:${LANGFUSE_SK}" \
  "${LANGFUSE_URL}/api/public/health" 2>/dev/null || echo "000")

if [ "${LF_HEALTH}" != "200" ]; then
  echo -e "${RED}ERROR: Langfuse not reachable at ${LANGFUSE_URL} (HTTP ${LF_HEALTH}).${NC}" >&2
  echo -e "${YELLOW}Ensure the Developer Edition was started with --with-ibm-telemetry (-i).${NC}" >&2
  echo -e "${YELLOW}Langfuse UI is at ${LANGFUSE_URL} (not https://localhost:8765/).${NC}" >&2
  exit 1
fi
echo -e "${GREEN}Langfuse    : reachable (HTTP ${LF_HEALTH})${NC}"

# ── Prepare output directory ───────────────────────────────────────────────────
mkdir -p "${OUTPUT_DIR}"
RUN_TS=$(date '+%Y%m%d_%H%M%S')
TRACE_FILE="${OUTPUT_DIR}/trace_${RUN_TS}.json"
if [ -z "${EXPORT_FILE}" ]; then
  EXPORT_FILE="${OUTPUT_DIR}/BOB_AGENT_ANALYTICS_REPORT_${RUN_TS}.md"
fi

# ── Step 1: Resolve agent name → agent ID ─────────────────────────────────────
print_header "Step 1 — Resolving agent '${AGENT_NAME}'"

_AGENTS_FILE="${OUTPUT_DIR}/_agents_${RUN_TS}.json"
curl -sf -H "Authorization: Bearer ${TOKEN}" \
  "${WXO_URL}/v1/orchestrate/agents" -o "${_AGENTS_FILE}" 2>/dev/null \
  || { echo -e "${RED}ERROR: Failed to list agents. Is the server running?${NC}" >&2; exit 1; }

AGENT_ID=$(python3 - "${AGENT_NAME}" "${_AGENTS_FILE}" <<'PYEOF'
import sys, json
agent_name, agents_file = sys.argv[1], sys.argv[2]
with open(agents_file) as f: raw = json.load(f)
agents = raw if isinstance(raw, list) else \
         raw.get('resources', raw.get('data', raw.get('items', raw.get('agents', []))))
for a in agents:
    e = a.get('entity', a)
    m = {**a.get('metadata', {}), **e}
    if m.get('name') == agent_name:
        print(m.get('agent_id') or m.get('id', ''))
        break
PYEOF
)
[ -n "${AGENT_ID}" ] || { echo -e "${RED}ERROR: Agent '${AGENT_NAME}' not found. Run: orchestrate agents list${NC}" >&2; exit 1; }
echo -e "${GREEN}Agent ID: ${AGENT_ID}${NC}"

# ── Step 2: Submit the run ─────────────────────────────────────────────────────
print_header "Step 2 — Sending test message"
echo -e "${CYAN}Message: ${TEST_MESSAGE}${NC}"

RUN_PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({'message': {'role': 'user', 'content': sys.argv[1]}, 'agent_id': sys.argv[2]}))" \
"${TEST_MESSAGE}" "${AGENT_ID}")

RUN_INIT=$(curl -sf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${RUN_PAYLOAD}" \
  "${WXO_URL}/v1/orchestrate/runs" 2>/dev/null)

RUN_ID=$(echo "${RUN_INIT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('run_id',''))")
THREAD_ID=$(echo "${RUN_INIT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('thread_id',''))")
[ -n "${RUN_ID}" ] || { echo -e "${RED}ERROR: No run_id returned. Check server is running.${NC}" >&2; exit 1; }
echo -e "${GREEN}Run ID   : ${RUN_ID}${NC}"
echo -e "${GREEN}Thread ID: ${THREAD_ID}${NC}"

# ── Step 3: Poll for completion and capture trace_id ──────────────────────────
print_header "Step 3 — Polling run for completion (timeout: ${POLL_TIMEOUT}s)"

ELAPSED=0
RUN_STATUS_FILE="${OUTPUT_DIR}/run_status_${RUN_TS}.json"
STATUS=""
while true; do
  curl -sf -H "Authorization: Bearer ${TOKEN}" \
    "${WXO_URL}/v1/orchestrate/runs/${RUN_ID}" \
    -o "${RUN_STATUS_FILE}" 2>/dev/null

  STATUS=$(python3 -c "import sys,json; d=json.load(open(sys.argv[1])); print(d.get('status','').lower())" "${RUN_STATUS_FILE}")
  case "${STATUS}" in completed|failed|cancelled) break ;; esac

  ELAPSED=$(( ELAPSED + 3 ))
  if [ "${ELAPSED}" -ge "${POLL_TIMEOUT}" ]; then
    echo -e "${RED}ERROR: Timed out after ${POLL_TIMEOUT}s (status: ${STATUS})${NC}" >&2; exit 1
  fi
  echo -e "  ${YELLOW}... ${ELAPSED}s — status: ${STATUS}${NC}"
  sleep 3
done

echo -e "${GREEN}Run status: ${STATUS}${NC}"

# Extract trace_id and final answer from the run response
TRACE_ID=$(python3 -c "import sys,json; d=json.load(open(sys.argv[1])); print(d.get('trace_id',''))" "${RUN_STATUS_FILE}")
FINAL_MESSAGE=$(python3 - "${RUN_STATUS_FILE}" <<'PYEOF'
import sys, json
d = json.load(open(sys.argv[1]))
msg = d.get('result', {}).get('data', {}).get('message', {})
content = msg.get('content', '')
if isinstance(content, list):
    content = ' '.join(i.get('text', '') for i in content if isinstance(i, dict) and i.get('response_type') == 'text')
print(content)
PYEOF
)

echo -e "${GREEN}Trace ID : ${TRACE_ID}${NC}"
echo -e "${GREEN}Response : ${FINAL_MESSAGE}${NC}"

[ -n "${TRACE_ID}" ] || { echo -e "${RED}ERROR: No trace_id in run response — ensure server was started with --with-ibm-telemetry.${NC}" >&2; exit 1; }

# ── Step 4: Export trace from Langfuse ────────────────────────────────────────
print_header "Step 4 — Exporting trace from Langfuse (${LANGFUSE_URL})"

# Allow a few seconds for trace ingestion
echo -e "${CYAN}Waiting 5s for Langfuse ingestion...${NC}"
sleep 5

# Fetch trace metadata + observations in one pass
python3 - "${LANGFUSE_URL}" "${LANGFUSE_PK}" "${LANGFUSE_SK}" \
          "${TRACE_ID}" "${TRACE_FILE}" "${AGENT_NAME}" "${RUN_TS}" \
          "${THREAD_ID}" "${RUN_ID}" "${FINAL_MESSAGE}" <<'PYEOF'
import sys, json, urllib.request, urllib.error, base64

lf_url, pk, sk, trace_id, out_file = sys.argv[1:6]
agent_name, ts, thread_id, run_id, final_msg = sys.argv[6:11]

creds = base64.b64encode(f"{pk}:{sk}".encode()).decode()
headers = {"Authorization": f"Basic {creds}"}

def fetch(path):
    req = urllib.request.Request(f"{lf_url}{path}", headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return {"error": str(e), "status": e.code}
    except Exception as e:
        return {"error": str(e)}

trace = fetch(f"/api/public/traces/{trace_id}")
obs   = fetch(f"/api/public/observations?traceId={trace_id}&limit=50")

export = {
    "trace_id":    trace_id,
    "agent_name":  agent_name,
    "run_id":      run_id,
    "thread_id":   thread_id,
    "exported_at": ts,
    "final_message": final_msg,
    "trace":       trace,
    "observations": obs.get("data", []),
    "totalCount":  obs.get("meta", {}).get("totalItems", len(obs.get("data", []))),
}

with open(out_file, "w") as f:
    json.dump(export, f, indent=2)

obs_count = len(export["observations"])
print(f"Exported: {obs_count} observations → {out_file}")
PYEOF

echo -e "${GREEN}Trace file: ${TRACE_FILE}${NC}"

# ── Step 4b: Build compact context document for Bob ───────────────────────────
CONTEXT_FILE="${OUTPUT_DIR}/analytics_context_${RUN_TS}.md"

python3 - "${TRACE_FILE}" "${CONTEXT_FILE}" "${AGENT_NAME}" "${TRACE_ID}" \
          "${RUN_TS}" "${THREAD_ID}" "${FINAL_MESSAGE}" <<'PYEOF'
import sys, json

trace_file, ctx_file = sys.argv[1:3]
agent_name, trace_id, ts, thread_id, final_msg = sys.argv[3:8]

with open(trace_file) as f:
    data = json.load(f)

trace   = data.get("trace", {})
obs_all = data.get("observations", [])

lines = [
    "# Agent Analytics Context",
    "",
    "| Field | Value |",
    "|---|---|",
    f"| Agent | `{agent_name}` |",
    f"| Trace ID | `{trace_id}` |",
    f"| Run timestamp | {ts} |",
    f"| Thread ID | `{thread_id}` |",
    f"| Run status | {trace.get('name','?')} — {trace.get('environment','?')} |",
    "",
    "## Agent Response",
    "",
    f"> {final_msg}",
    "",
    "## Observations",
    "",
    "| # | Name | Type | Level | Duration ms |",
    "|---|---|---|---|---|",
]

for i, o in enumerate(obs_all, 1):
    name  = o.get("name", "?")
    otype = o.get("type", "?")
    level = o.get("level", "?")
    start = o.get("startTime", "")
    end   = o.get("endTime", "")
    dur   = "?"
    if start and end:
        try:
            from datetime import datetime
            fmt = "%Y-%m-%dT%H:%M:%S.%fZ"
            dur = str(int((datetime.strptime(end, fmt) - datetime.strptime(start, fmt)).total_seconds() * 1000))
        except Exception:
            pass
    lines.append(f"| {i} | {name} | {otype} | {level} | {dur} |")

lines += [
    "",
    "## Full Trace JSON (truncated to 150 lines)",
    "",
    "```json",
]

trace_lines = json.dumps(data, indent=2).splitlines()
lines += trace_lines[:150]
if len(trace_lines) > 150:
    lines.append(f"... ({len(trace_lines) - 150} more lines — see full file)")
lines += ["```", "", f"_Full trace: {trace_file}_"]

with open(ctx_file, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"Context: {len(lines)} lines ({len(obs_all)} observations)")
PYEOF

if [ "${TRACE_ONLY}" = "true" ]; then
  echo ""
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${GREEN}--trace-only set. Skipping Bob analysis.${NC}"
  echo -e "${GREEN}Trace file : ${TRACE_FILE}${NC}"
  exit 0
fi

# ── Step 5: Invoke Bob CLI ─────────────────────────────────────────────────────
print_header "Step 5 — IBM Bob CLI analysis (mode: ${BOB_MODE})"

cat > "${EXPORT_FILE}" <<HEADER
## Run Metadata

| Field | Value |
|---|---|
| Agent | ${AGENT_NAME} |
| Trace ID | ${TRACE_ID} |
| Run ID | ${RUN_ID} |
| Thread ID | ${THREAD_ID} |
| Bob mode | ${BOB_MODE} |
| Generated | $(date '+%Y-%m-%d %H:%M:%S') |
| Trace file | ${TRACE_FILE} |
| Langfuse | ${LANGFUSE_URL} |
| Langfuse UI | ${LANGFUSE_URL}/project/orchestrate-lite/traces/${TRACE_ID} |

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

# ── Step 5b: Clean the exported file ──────────────────────────────────────────
python3 - "${EXPORT_FILE}" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    raw = f.read()

# Remove <thinking>…</thinking> blocks (including multiline)
clean = re.sub(r'<thinking>.*?</thinking>\n?', '', raw, flags=re.DOTALL)

# Remove [using tool …] lines and ---output--- fences
clean = re.sub(r'\[using tool [^\]]+\]\n?', '', clean)
clean = re.sub(r'---output---\n?', '', clean)

# If the analysis heading appears more than once (intermediate + final output),
# keep only the metadata header block + last analysis body.
marker = '# Agent Analytics Report'
parts = clean.split(marker)
if len(parts) > 2:
    clean = parts[0].rstrip() + '\n\n' + marker + parts[-1]

# Collapse runs of 3+ blank lines to 2
clean = re.sub(r'\n{3,}', '\n\n', clean)

with open(sys.argv[1], 'w') as f:
    f.write(clean.strip() + '\n')

print(f"Cleaned: {sys.argv[1]}")
PYEOF

# ── Footer ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}Agent    : ${AGENT_NAME}${NC}"
echo -e "${GREEN}Trace ID : ${TRACE_ID}${NC}"
echo -e "${GREEN}Trace    : ${TRACE_FILE}${NC}"
echo -e "${GREEN}Langfuse : ${LANGFUSE_URL}${NC}"
echo -e "${GREEN}Bob mode : ${BOB_MODE}${NC}"
echo -e "${GREEN}Report   : ${EXPORT_FILE}${NC}"
