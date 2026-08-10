#!/usr/bin/env bash
# wxo_bob_session_analytics.sh
# Inspect a specific agent's behaviour across all runs in a time window.
# Queries the local Langfuse API directly — no new run is triggered.
#
# Pipeline:
#   1. Fetch all Langfuse traces in [--from, --to] that belong to --agent
#   2. For each trace, fetch its observations
#   3. Build a consolidated context document (summary table + per-trace detail)
#   4. bob run --mode <mode> "<context+question>"  → AI analysis
#   5. Save report to <output-dir>/BOB_SESSION_ANALYTICS_REPORT_<ts>.md
#
# Usage:
#   bash wxo_bob_session_analytics.sh [OPTIONS]
#
# Options:
#   --agent      -n   Agent name to filter on. Default: agent_hello_world
#   --from       -f   Start of time window (ISO-8601 or YYYY-MM-DD). Required.
#   --to         -t   End of time window   (ISO-8601 or YYYY-MM-DD). Default: now.
#   --output-dir -o   Directory for generated files. Default: ./agent-analytics
#   --question   -q   Question for Bob. Default: standard session analysis question.
#   --bob-mode        Bob run mode. Default: ask
#   --export-file     Custom path for Bob report.
#                     Default: <output-dir>/BOB_SESSION_ANALYTICS_REPORT_<ts>.md
#   --env-file   -e   Path to a .env file. Default: .env
#   --langfuse-url    Langfuse API base URL. Default: http://localhost:3010
#   --langfuse-pk     Langfuse public key.  Default: pk-lf-orchestrate
#   --langfuse-sk     Langfuse secret key.  Default: sk-lf-orchestrate
#   --trace-limit N   Max traces to fetch per page. Default: 100
#   --obs-limit N     Max observations fetched per trace. Default: 50
#   --ctx-lines N     Max JSON lines per trace in the Bob context. Default: 80
#   --trace-only      Export traces only; skip Bob analysis.
#   --help            Show this message and exit.
#
# Requirements:
#   - Langfuse running locally (Developer Edition started with --with-ibm-telemetry)
#   - python3
#   - bob CLI (npm install -g @ibm/bob-cli) — unless --trace-only is set
#   - BOB_API_KEY env var set (or in .env) — unless --trace-only is set
#
# Examples:
#   # Inspect agent_hello_world on a specific day:
#   bash wxo_bob_session_analytics.sh --from 2026-08-10 --to 2026-08-11
#
#   # Inspect a different agent over a two-hour window:
#   bash wxo_bob_session_analytics.sh \
#     -n my_agent \
#     --from 2026-08-10T08:00:00Z \
#     --to   2026-08-10T10:00:00Z
#
#   # Export traces only (no Bob analysis):
#   bash wxo_bob_session_analytics.sh --from 2026-08-10 --trace-only
#
#   # Deeper analysis:
#   bash wxo_bob_session_analytics.sh --from 2026-08-10 --bob-mode arch-review

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── Defaults ───────────────────────────────────────────────────────────────────
AGENT_NAME="agent_hello_world"
FROM_TIME=""
TO_TIME=""
OUTPUT_DIR="./agent-analytics"
ENV_FILE=".env"
BOB_MODE="ask"
EXPORT_FILE=""
TRACE_ONLY=false
LANGFUSE_URL="http://localhost:3010"
LANGFUSE_PK="pk-lf-orchestrate"
LANGFUSE_SK="sk-lf-orchestrate"
TRACE_LIMIT=100
OBS_LIMIT=50
CTX_LINES=80
QUESTION="You are analysing a watsonx Orchestrate Agent Analytics session export.
This report covers ALL runs of the agent in a specific time window.
Provide a structured analysis with:
1. Session summary — agent name, time window, total runs, overall success rate.
2. Run-by-run table — trace ID, timestamp, duration, status, final response snippet.
3. Behaviour patterns — are responses consistent? Any variation in tool usage or latency?
4. Errors or anomalies — failed runs, unexpected observations, latency outliers.
5. Recommendation — is the agent behaving correctly and consistently across the session?"

# ── Argument parsing ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --agent|-n)       AGENT_NAME="$2";    shift 2 ;;
    --from|-f)        FROM_TIME="$2";     shift 2 ;;
    --to|-t)          TO_TIME="$2";       shift 2 ;;
    --output-dir|-o)  OUTPUT_DIR="$2";    shift 2 ;;
    --question|-q)    QUESTION="$2";      shift 2 ;;
    --bob-mode)       BOB_MODE="$2";      shift 2 ;;
    --export-file)    EXPORT_FILE="$2";   shift 2 ;;
    --env-file|-e)    ENV_FILE="$2";      shift 2 ;;
    --langfuse-url)   LANGFUSE_URL="$2";  shift 2 ;;
    --langfuse-pk)    LANGFUSE_PK="$2";   shift 2 ;;
    --langfuse-sk)    LANGFUSE_SK="$2";   shift 2 ;;
    --trace-limit)    TRACE_LIMIT="$2";   shift 2 ;;
    --obs-limit)      OBS_LIMIT="$2";     shift 2 ;;
    --ctx-lines)      CTX_LINES="$2";     shift 2 ;;
    --trace-only)     TRACE_ONLY=true;    shift ;;
    --help)
      sed -n -e '/^#!/d' -e '/^#/!q' -e 's/^# \{0,2\}//p' "$0"
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
  esac
done

# ── Validate required args ─────────────────────────────────────────────────────
if [ -z "${FROM_TIME}" ]; then
  echo -e "${RED}ERROR: --from is required. Example: --from 2026-08-10 or --from 2026-08-10T08:00:00Z${NC}" >&2
  exit 1
fi

# Normalise bare YYYY-MM-DD to full ISO-8601 (Langfuse requires the T form)
[[ "${FROM_TIME}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && FROM_TIME="${FROM_TIME}T00:00:00Z"
[[ "${TO_TIME}"   =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && TO_TIME="${TO_TIME}T23:59:59Z"

# Default --to to now (UTC)
if [ -z "${TO_TIME}" ]; then
  TO_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

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

# ── Verify Langfuse is reachable ───────────────────────────────────────────────
LF_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "${LANGFUSE_PK}:${LANGFUSE_SK}" \
  "${LANGFUSE_URL}/api/public/health" 2>/dev/null || echo "000")

if [ "${LF_HEALTH}" != "200" ]; then
  echo -e "${RED}ERROR: Langfuse not reachable at ${LANGFUSE_URL} (HTTP ${LF_HEALTH}).${NC}" >&2
  echo -e "${YELLOW}Ensure the Developer Edition was started with --with-ibm-telemetry (-i).${NC}" >&2
  exit 1
fi

echo -e "${CYAN}Agent       : ${AGENT_NAME}${NC}"
echo -e "${CYAN}From        : ${FROM_TIME}${NC}"
echo -e "${CYAN}To          : ${TO_TIME}${NC}"
echo -e "${CYAN}Langfuse    : ${LANGFUSE_URL} (reachable)${NC}"

# ── Prepare output directory ───────────────────────────────────────────────────
mkdir -p "${OUTPUT_DIR}"
RUN_TS=$(date '+%Y%m%d_%H%M%S')
TRACES_FILE="${OUTPUT_DIR}/session_traces_${RUN_TS}.json"
CONTEXT_FILE="${OUTPUT_DIR}/session_context_${RUN_TS}.md"
if [ -z "${EXPORT_FILE}" ]; then
  EXPORT_FILE="${OUTPUT_DIR}/BOB_SESSION_ANALYTICS_REPORT_${RUN_TS}.md"
fi

# ── Step 1: Fetch all matching traces from Langfuse ───────────────────────────
print_header "Step 1 — Fetching traces for '${AGENT_NAME}' [${FROM_TIME} → ${TO_TIME}]"

python3 - "${LANGFUSE_URL}" "${LANGFUSE_PK}" "${LANGFUSE_SK}" \
          "${AGENT_NAME}" "${FROM_TIME}" "${TO_TIME}" \
          "${TRACES_FILE}" "${TRACE_LIMIT}" "${OBS_LIMIT}" <<'PYEOF'
import sys, json, urllib.request, urllib.error, urllib.parse, base64

lf_url, pk, sk   = sys.argv[1:4]
agent_name        = sys.argv[4]
from_ts, to_ts    = sys.argv[5], sys.argv[6]
out_file          = sys.argv[7]
trace_limit       = int(sys.argv[8])
obs_limit         = int(sys.argv[9])

creds   = base64.b64encode(f"{pk}:{sk}".encode()).decode()
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

# Fetch traces filtered by time window and trace name (all wxO traces = "LangGraph")
params = urllib.parse.urlencode({
    "limit":         trace_limit,
    "fromTimestamp": from_ts,
    "toTimestamp":   to_ts,
    "name":          "LangGraph",
})
resp = fetch(f"/api/public/traces?{params}")
all_traces = resp.get("data", [])
total_lf   = resp.get("meta", {}).get("totalItems", len(all_traces))

# Filter client-side by agent name (stored in trace input.current_agent)
matched = []
for t in all_traces:
    inp = t.get("input", {})
    if isinstance(inp, dict) and inp.get("current_agent") == agent_name:
        matched.append(t)

print(f"Langfuse returned {len(all_traces)} traces in window "
      f"(total in project: {total_lf}); {len(matched)} match agent '{agent_name}'")

if not matched:
    json.dump({"agent": agent_name, "from": from_ts, "to": to_ts, "traces": []}, open(out_file, "w"))
    sys.exit(0)

# Fetch observations for each matched trace
result = []
for t in matched:
    tid  = t["id"]
    obs  = fetch(f"/api/public/observations?traceId={tid}&limit={obs_limit}")
    result.append({
        "trace_id":    tid,
        "timestamp":   t.get("timestamp"),
        "session_id":  t.get("sessionId"),
        "agent":       agent_name,
        "trace":       t,
        "observations": obs.get("data", []),
    })
    print(f"  trace {tid[:12]}… — {len(obs.get('data', []))} observations")

export = {
    "agent":     agent_name,
    "from":      from_ts,
    "to":        to_ts,
    "run_count": len(result),
    "traces":    result,
}
with open(out_file, "w") as f:
    json.dump(export, f, indent=2)

print(f"Saved: {len(result)} traces → {out_file}")
PYEOF

TRACE_COUNT=$(python3 -c "import json; d=json.load(open('${TRACES_FILE}')); print(d.get('run_count', 0))")
echo -e "${GREEN}Traces matched: ${TRACE_COUNT}${NC}"

if [ "${TRACE_COUNT}" = "0" ]; then
  echo -e "${YELLOW}No traces found for '${AGENT_NAME}' in [${FROM_TIME}, ${TO_TIME}].${NC}"
  echo -e "${YELLOW}Check the time window or agent name. Use --trace-limit to increase page size.${NC}"
  exit 1
fi

# ── Step 2: Build consolidated context document ───────────────────────────────
print_header "Step 2 — Building session context document"

python3 - "${TRACES_FILE}" "${CONTEXT_FILE}" "${CTX_LINES}" <<'PYEOF'
import sys, json
from datetime import datetime

traces_file, ctx_file = sys.argv[1], sys.argv[2]
ctx_lines = int(sys.argv[3])

with open(traces_file) as f:
    data = json.load(f)

agent    = data["agent"]
from_ts  = data["from"]
to_ts    = data["to"]
traces   = data["traces"]

def fmt_ms(start, end):
    if not start or not end:
        return "?"
    try:
        fmt = "%Y-%m-%dT%H:%M:%S.%fZ"
        return str(int((datetime.strptime(end, fmt) - datetime.strptime(start, fmt)).total_seconds() * 1000))
    except Exception:
        return "?"

lines = [
    "# Agent Session Analytics Context",
    "",
    "| Field | Value |",
    "|---|---|",
    f"| Agent | `{agent}` |",
    f"| From  | {from_ts} |",
    f"| To    | {to_ts} |",
    f"| Total runs | {len(traces)} |",
    "",
    "## Run Summary Table",
    "",
    "| # | Trace ID | Timestamp | Duration ms | Observations | Response snippet |",
    "|---|---|---|---|---|---|",
]

for i, entry in enumerate(traces, 1):
    tid   = entry["trace_id"]
    ts    = entry.get("timestamp", "?")
    obs   = entry.get("observations", [])
    trace = entry.get("trace", {})

    # Duration: first to last observation time
    times = [(o.get("startTime",""), o.get("endTime","")) for o in obs if o.get("startTime") and o.get("endTime")]
    starts = [t[0] for t in times]
    ends   = [t[1] for t in times]
    dur    = fmt_ms(min(starts) if starts else "", max(ends) if ends else "")

    # Final response from trace output
    out = trace.get("output", {})
    if isinstance(out, dict):
        msgs = out.get("messages", [])
        snippet = msgs[-1].get("content", "")[:80] if msgs else str(out)[:80]
    else:
        snippet = str(out)[:80]
    snippet = snippet.replace("|", "/").replace("\n", " ")

    lines.append(f"| {i} | `{tid[:16]}…` | {ts[:19]} | {dur} | {len(obs)} | {snippet} |")

# Per-trace detail sections
for i, entry in enumerate(traces, 1):
    tid   = entry["trace_id"]
    ts    = entry.get("timestamp", "?")
    obs   = entry.get("observations", [])

    lines += [
        "",
        f"## Run {i} — `{tid}`",
        f"Timestamp: {ts}",
        "",
        "### Observations",
        "",
        "| # | Name | Type | Level | Duration ms |",
        "|---|---|---|---|---|",
    ]
    for j, o in enumerate(obs, 1):
        dur = fmt_ms(o.get("startTime",""), o.get("endTime",""))
        lines.append(f"| {j} | {o.get('name','?')} | {o.get('type','?')} | {o.get('level','?')} | {dur} |")

    lines += ["", f"### Trace JSON (first {ctx_lines} lines)", "", "```json"]
    trace_lines = json.dumps(entry, indent=2).splitlines()
    lines += trace_lines[:ctx_lines]
    if len(trace_lines) > ctx_lines:
        lines.append(f"... ({len(trace_lines) - ctx_lines} more lines — see full file)")
    lines += ["```"]

lines += ["", f"_Full traces: {traces_file}_"]

with open(ctx_file, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"Context: {len(lines)} lines ({len(traces)} runs)")
PYEOF

echo -e "${GREEN}Context file: ${CONTEXT_FILE}${NC}"

if [ "${TRACE_ONLY}" = "true" ]; then
  echo ""
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${GREEN}--trace-only set. Skipping Bob analysis.${NC}"
  echo -e "${GREEN}Traces file  : ${TRACES_FILE}${NC}"
  echo -e "${GREEN}Context file : ${CONTEXT_FILE}${NC}"
  exit 0
fi

# ── Step 3: Invoke Bob CLI ─────────────────────────────────────────────────────
print_header "Step 3 — IBM Bob CLI analysis (mode: ${BOB_MODE})"

cat > "${EXPORT_FILE}" <<HEADER
## Session Metadata

| Field | Value |
|---|---|
| Agent | ${AGENT_NAME} |
| From | ${FROM_TIME} |
| To | ${TO_TIME} |
| Runs found | ${TRACE_COUNT} |
| Bob mode | ${BOB_MODE} |
| Generated | $(date '+%Y-%m-%d %H:%M:%S') |
| Traces file | ${TRACES_FILE} |
| Langfuse | ${LANGFUSE_URL} |

---

HEADER

echo -e "${CYAN}Building prompt → bob run --mode \"${BOB_MODE}\" \"<context+question>\"${NC}"
echo -e "${CYAN}Output → terminal + ${EXPORT_FILE}${NC}"
echo ""

CONTEXT_CONTENT=$(cat "${CONTEXT_FILE}")
FULL_PROMPT="${CONTEXT_CONTENT}

${QUESTION}"

bob run \
  --mode "${BOB_MODE}" \
  --accept-license \
  "${FULL_PROMPT}" | tee -a "${EXPORT_FILE}"

# ── Step 3b: Clean the exported file ──────────────────────────────────────────
python3 - "${EXPORT_FILE}" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    raw = f.read()

clean = re.sub(r'<thinking>.*?</thinking>\n?', '', raw, flags=re.DOTALL)
clean = re.sub(r'\[using tool [^\]]+\]\n?', '', clean)
clean = re.sub(r'---output---\n?', '', clean)

marker = '# Agent Session Analytics Report'
parts = clean.split(marker)
if len(parts) > 2:
    clean = parts[0].rstrip() + '\n\n' + marker + parts[-1]

clean = re.sub(r'\n{3,}', '\n\n', clean)

with open(sys.argv[1], 'w') as f:
    f.write(clean.strip() + '\n')

print(f"Cleaned: {sys.argv[1]}")
PYEOF

# ── Footer ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}Agent        : ${AGENT_NAME}${NC}"
echo -e "${GREEN}Window       : ${FROM_TIME} → ${TO_TIME}${NC}"
echo -e "${GREEN}Runs         : ${TRACE_COUNT}${NC}"
echo -e "${GREEN}Traces file  : ${TRACES_FILE}${NC}"
echo -e "${GREEN}Langfuse     : ${LANGFUSE_URL}${NC}"
echo -e "${GREEN}Bob mode     : ${BOB_MODE}${NC}"
echo -e "${GREEN}Report       : ${EXPORT_FILE}${NC}"
