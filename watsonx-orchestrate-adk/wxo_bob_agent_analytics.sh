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
#   5. Save all files to <output-dir>/<agent_name>/<timestamp>/
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
#   --poll-timeout N  Seconds before giving up on a running run. Default: 120
#   --poll-interval N Seconds between status polls. Default: 3
#   --obs-limit N     Max observations fetched from Langfuse. Default: 50
#   --ctx-lines N     Max JSON lines included in the Bob context. Default: 150
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

# ── Load environment variables first so every subsequent command inherits them ─
if [ -f ".env" ]; then
  set -a; source ".env"; set +a
fi

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
POLL_INTERVAL=3
OBS_LIMIT=50
CTX_LINES=150
QUESTION="You are analysing a watsonx Orchestrate Agent Analytics (Langfuse observability) JSON export.
Provide a concise structured report with:
1. Run summary — agent name, trace ID, overall status, total duration.
2. Step-by-step trace — list each observation with type, name, duration, and status.
3. Tool calls detected — which tools were invoked and with what arguments.
4. Errors or anomalies — any failed steps or unexpected observations.
5. Production-hardening checks:
   a. service.name — is it set to a meaningful value (e.g. wxo-agent-runtime) or still default/missing? Recommend fixing if not set.
   b. ls_provider label — if ls_provider is 'openai', note that this is the watsonx-via-OpenAI-adapter label; advise ensuring dashboards/alerts account for this discrepancy.
   c. Latency baseline — LLM latency and total trace duration. Flag if LLM latency exceeds 10 s or total trace exceeds 15 s with no tool calls as warranting investigation.
6. Recommendation — is the agent behaving as expected? Any issues to address?"

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
    --poll-timeout)     POLL_TIMEOUT="$2";  shift 2 ;;
    --poll-interval)    POLL_INTERVAL="$2"; shift 2 ;;
    --obs-limit)        OBS_LIMIT="$2";     shift 2 ;;
    --ctx-lines)        CTX_LINES="$2";     shift 2 ;;
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

# ── Verify Langfuse is reachable AND credentials are valid ────────────────────
# /api/public/health accepts any credentials — use /api/public/projects instead,
# which requires valid Basic Auth, to catch wrong keys early.
LF_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "${LANGFUSE_PK}:${LANGFUSE_SK}" \
  "${LANGFUSE_URL}/api/public/projects" 2>/dev/null || echo "000")

if [ "${LF_HEALTH}" = "401" ]; then
  echo -e "${RED}ERROR: Langfuse credentials rejected (HTTP 401) at ${LANGFUSE_URL}.${NC}" >&2
  echo -e "${YELLOW}Default keys: pk-lf-orchestrate / sk-lf-orchestrate${NC}" >&2
  echo -e "${YELLOW}Override with: --langfuse-pk <key> --langfuse-sk <key>${NC}" >&2
  exit 1
fi
if [ "${LF_HEALTH}" != "200" ]; then
  echo -e "${RED}ERROR: Langfuse not reachable at ${LANGFUSE_URL} (HTTP ${LF_HEALTH}).${NC}" >&2
  echo -e "${YELLOW}Ensure the Developer Edition was started with --with-ibm-telemetry (-i).${NC}" >&2
  echo -e "${YELLOW}Langfuse UI is at ${LANGFUSE_URL} (not https://localhost:8765/).${NC}" >&2
  exit 1
fi
echo -e "${GREEN}Langfuse    : reachable + credentials valid (HTTP ${LF_HEALTH})${NC}"

# ── Prepare output directory — one sub-folder per agent per run ───────────────
RUN_TS=$(date '+%Y%m%d_%H%M%S')
OUTPUT_DIR="${OUTPUT_DIR}/${AGENT_NAME}/${RUN_TS}"
mkdir -p "${OUTPUT_DIR}"
TRACE_FILE="${OUTPUT_DIR}/trace.json"
if [ -z "${EXPORT_FILE}" ]; then
  EXPORT_FILE="${OUTPUT_DIR}/BOB_AGENT_ANALYTICS_REPORT.md"
fi

# ── Step 1: Resolve agent name → agent ID ─────────────────────────────────────
print_header "Step 1 — Resolving agent '${AGENT_NAME}'"

_AGENTS_FILE="${OUTPUT_DIR}/_agents.json"
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
print_header "Step 3 — Polling run for completion (timeout: ${POLL_TIMEOUT}s, interval: ${POLL_INTERVAL}s)"

ELAPSED=0
RUN_STATUS_FILE="${OUTPUT_DIR}/run_status.json"
STATUS=""
while true; do
  curl -sf -H "Authorization: Bearer ${TOKEN}" \
    "${WXO_URL}/v1/orchestrate/runs/${RUN_ID}" \
    -o "${RUN_STATUS_FILE}" 2>/dev/null

  STATUS=$(python3 -c "import sys,json; d=json.load(open(sys.argv[1])); print(d.get('status','').lower())" "${RUN_STATUS_FILE}")
  case "${STATUS}" in completed|failed|cancelled) break ;; esac

  ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
  if [ "${ELAPSED}" -ge "${POLL_TIMEOUT}" ]; then
    echo -e "${RED}ERROR: Timed out after ${POLL_TIMEOUT}s (status: ${STATUS})${NC}" >&2; exit 1
  fi
  echo -e "  ${YELLOW}... ${ELAPSED}s — status: ${STATUS}${NC}"
  sleep "${POLL_INTERVAL}"
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
          "${THREAD_ID}" "${RUN_ID}" "${FINAL_MESSAGE}" "${OBS_LIMIT}" <<'PYEOF'
import sys, json, urllib.request, urllib.error, base64

lf_url, pk, sk, trace_id, out_file = sys.argv[1:6]
agent_name, ts, thread_id, run_id, final_msg = sys.argv[6:11]
obs_limit = int(sys.argv[11]) if len(sys.argv) > 11 else 50

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
obs   = fetch(f"/api/public/observations?traceId={trace_id}&limit={obs_limit}")

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
CONTEXT_FILE="${OUTPUT_DIR}/analytics_context.md"

python3 - "${TRACE_FILE}" "${CONTEXT_FILE}" "${AGENT_NAME}" "${TRACE_ID}" \
          "${RUN_TS}" "${THREAD_ID}" "${FINAL_MESSAGE}" "${CTX_LINES}" <<'PYEOF'
import sys, json

trace_file, ctx_file = sys.argv[1:3]
agent_name, trace_id, ts, thread_id, final_msg = sys.argv[3:8]
ctx_lines = int(sys.argv[8]) if len(sys.argv) > 8 else 150

with open(trace_file) as f:
    data = json.load(f)

trace   = data.get("trace", {})
obs_all = data.get("observations", [])

# ── Extract production-hardening fields ──────────────────────────────────────
service_name = trace.get("metadata", {}).get("service.name") or \
               trace.get("tags", [None])[0] if trace.get("tags") else None
if not service_name:
    # scan top-level observation metadata
    for o in obs_all:
        meta = o.get("metadata") or {}
        if isinstance(meta, dict) and meta.get("service.name"):
            service_name = meta["service.name"]
            break
service_name = service_name or "NOT SET"

ls_provider = None
for o in obs_all:
    meta = o.get("metadata") or {}
    if isinstance(meta, dict) and meta.get("ls_provider"):
        ls_provider = meta["ls_provider"]
        break
ls_provider = ls_provider or "unknown"

# LLM latency: duration of the generation observation
llm_latency_ms = "?"
total_ms       = "?"
try:
    from datetime import datetime
    fmt = "%Y-%m-%dT%H:%M:%S.%fZ"
    durations = []
    for o in obs_all:
        s, e = o.get("startTime",""), o.get("endTime","")
        if s and e:
            durations.append((
                datetime.strptime(s, fmt),
                datetime.strptime(e, fmt),
                o.get("type",""),
            ))
    if durations:
        total_ms = str(int((max(d[1] for d in durations) - min(d[0] for d in durations)).total_seconds() * 1000))
    for start_t, end_t, otype in durations:
        if otype in ("GENERATION", "generation"):
            llm_latency_ms = str(int((end_t - start_t).total_seconds() * 1000))
            break
except Exception:
    pass

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
    "## Production-Hardening Signals",
    "",
    "| Signal | Value | Note |",
    "|---|---|---|",
    f"| service.name | `{service_name}` | {'⚠ Recommend setting to meaningful value (e.g. wxo-agent-runtime)' if service_name == 'NOT SET' else '✓'} |",
    f"| ls_provider | `{ls_provider}` | {'⚠ watsonx-via-OpenAI-adapter label — account for this in dashboard/alert filters' if ls_provider == 'openai' else '✓'} |",
    f"| LLM latency | {llm_latency_ms} ms | {'⚠ Exceeds 10 s threshold' if llm_latency_ms.isdigit() and int(llm_latency_ms) > 10000 else '✓'} |",
    f"| Total trace | {total_ms} ms | {'⚠ Exceeds 15 s threshold (no tool calls expected)' if total_ms.isdigit() and int(total_ms) > 15000 else '✓'} |",
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
    f"## Full Trace JSON (truncated to {ctx_lines} lines)",
    "",
    "```json",
]

trace_lines = json.dumps(data, indent=2).splitlines()
lines += trace_lines[:ctx_lines]
if len(trace_lines) > ctx_lines:
    lines.append(f"... ({len(trace_lines) - ctx_lines} more lines — see full file)")
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

BOB_START=$(date +%s)
bob run \
  --mode "${BOB_MODE}" \
  --accept-license \
  "${FULL_PROMPT}" | tee -a "${EXPORT_FILE}"
BOB_END=$(date +%s)
BOB_ELAPSED=$(( BOB_END - BOB_START ))

# ── Step 5b: Clean the exported file ──────────────────────────────────────────
python3 - "${EXPORT_FILE}" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    raw = f.read()

# ── 0a. Strip ANSI escape codes (Bob CLI wraps terminal output in colour codes;
#        they prevent box-drawing detection from working correctly) ─────────────
clean = re.sub(r'\x1b\[[0-9;]*[mK]', '', raw)

# ── 0b. Fix Mermaid sequence diagram keyword (LLM often emits "sequence diagram") ─
clean = re.sub(r'(```mermaid\s*)sequence diagram', r'\1sequenceDiagram', clean, flags=re.IGNORECASE)

# ── 1. Remove <thinking> blocks ───────────────────────────────────────────────
clean = re.sub(r'<thinking>.*?</thinking>\n?', '', clean, flags=re.DOTALL)

# ── 2. Remove [using tool …] lines and ---output--- fences ────────────────────
clean = re.sub(r'\[using tool [^\]]+\]\n?', '', clean)
clean = re.sub(r'---output---\n?', '', clean)

# ── 3. Strip Bob's conversation-frame wrapper lines ───────────────────────────
# Matches: "User (N) YYYY-MM-DD …" / "Assistant (N) YYYY-MM-DD …"
# and the surrounding ────… separator lines (Unicode U+2500 BOX DRAWINGS LIGHT HORIZONTAL)
clean = re.sub(r'^[─\-]{10,}\n', '', clean, flags=re.MULTILINE)
clean = re.sub(r'^(?:User|Assistant)\s*\(\d+\)[^\n]*\n', '', clean, flags=re.MULTILINE)

# ── 4. Strip trailing whitespace on every line (terminal padding) ─────────────
clean = re.sub(r'[ \t]+$', '', clean, flags=re.MULTILINE)

# ── 5. Convert Unicode box-drawing tables to GFM pipe tables ──────────────────
# Strategy: collect consecutive lines that start with │ (or ├/└/┌) into a block,
# convert each │-delimited row into a GFM row, insert separator after first row.
BOX_CHARS = '┌┬┐├┼┤└┴┘─'

def is_box_border(line):
    """True for pure border lines: ┌───┬───┐  ├───┼───┤  └───┴───┘"""
    stripped = line.strip()
    return bool(stripped) and all(c in BOX_CHARS for c in stripped)

def box_row_to_gfm(line):
    """Convert  │ cell1 │ cell2 │  →  | cell1 | cell2 |"""
    # split on │, drop first/last empty fragments
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
        # Pure border line — skip
        i += 1
        continue

    if stripped.startswith('│'):
        # Collect all consecutive │-rows and border lines
        raw_rows = []
        while i < len(lines) and (lines[i].strip().startswith('│') or is_box_border(lines[i].strip())):
            if not is_box_border(lines[i].strip()):
                raw_rows.append(lines[i])
            i += 1
        # Detect single-column prose blocks (Agent Response blockquote style):
        # every row has exactly one │-delimited cell
        def col_count_of(row):
            return len(row.split('│')) - 2  # fragments between first and last │
        if raw_rows and all(col_count_of(r) == 1 for r in raw_rows):
            # Render as Markdown blockquote
            for r in raw_rows:
                cell = r.split('│')[1].strip()
                if cell:
                    out.append('> ' + cell)
        else:
            table_rows = [box_row_to_gfm(r) for r in raw_rows]
            # Insert GFM separator after first (header) row
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
# A bare title: non-empty line, not already a heading/list/fence/table/blank,
# preceded and followed by a blank line, and not the very first block.
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
            # Must look like a title: no terminal punctuation, no inline spaces after colon
            and not s.endswith('.')
            and not s.endswith(',')
            and not s.endswith(':')
            # Must not be a plain --- separator that survived the earlier pass
            and s not in ('---', '–––', '===')
            # Must contain at least one letter (exclude pure symbols / numbers)
            and any(c.isalpha() for c in s)
            # Short enough to be a heading
            and len(s) <= 60
        )
        if is_candidate:
            result.append('### ' + s)
        else:
            result.append(line)
    return '\n'.join(result)

clean = promote_bare_headings(clean)

# ── 8. Remove echoed prompt context block before Bob's answer ────────────────
# Bob echoes the full prompt back before its answer. Strip everything between
# the first "---\n" (end of the metadata header we wrote) and the first real
# Bob heading (### 1. or # Agent Analytics Report).
clean = re.sub(
    r'(---\n)\n.*?(?=(?:###\s*1\.|# Agent Analytics Report))',
    r'\1\n',
    clean,
    count=1,
    flags=re.DOTALL,
)

# ── 9. De-duplicate repeated report body ─────────────────────────────────────
marker = '# Agent Analytics Report'
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

# ── Footer ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}Agent    : ${AGENT_NAME}${NC}"
echo -e "${GREEN}Trace ID : ${TRACE_ID}${NC}"
echo -e "${GREEN}Trace    : ${TRACE_FILE}${NC}"
echo -e "${GREEN}Langfuse : ${LANGFUSE_URL}${NC}"
echo -e "${GREEN}Bob mode : ${BOB_MODE}${NC}"
echo -e "${GREEN}Bob time : ${BOB_ELAPSED} s${NC}"
echo -e "${GREEN}Report   : ${EXPORT_FILE}${NC}"
