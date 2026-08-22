---
name: wxo-agent-analytics
description: >
  Use when the user wants to inspect, analyze, or review watsonx Orchestrate
  agent behavior using Langfuse traces and IBM Bob. Handles both a single new
  test run and bulk session history. Trigger phrases: "analyze agent behavior",
  "review agent analytics", "inspect agent traces", "run agent analytics",
  "check agent performance", "review langfuse traces", "wxo_bob_agent_analytics",
  "wxo_bob_session_analytics", "agent trace analysis", "agent behavior review".
metadata:
  disable-model-invocation: false
---

# wxo-agent-analytics

Analyze watsonx Orchestrate agent behavior by running a Langfuse trace pipeline
and asking IBM Bob to reason over the structured execution data.

Two scripts are available:

| Script | When to use |
|---|---|
| `wxo_bob_agent_analytics.sh` | Fire a **new test run**, capture its trace, analyze it immediately |
| `wxo_bob_session_analytics.sh` | Inspect **all past runs** within a time window — no new run needed |

---

## Step 1 — Verify prerequisites

Use `execute_command` to confirm the environment is ready:

```bash
which bob && bob --version 2>&1 | head -3
which jq
curl -s http://localhost:3010/api/public/health
orchestrate env list 2>/dev/null | grep active
```

Confirm:
- `bob` is on PATH and returns a version.
- `jq` is available.
- Langfuse returns `{"status":"ok"}` at `http://localhost:3010`.
- The active `orchestrate` environment is `local`.

If Langfuse is unreachable or no environment is active, tell the user to run
`bash wxo_local_start.sh` first (guide §6.2).

If `BOB_API_KEY` is not set, remind the user to fill it in
`watsonx-orchestrate-adk/.env` (guide §6.3).

---

## Step 2 — Choose the right script

Use `ask_followup_question` to determine the user's intent:

> "Do you want to fire a **new test message** against the agent and analyze that
> run, or inspect the agent's **past runs** from a specific time window?"

- **New test run** → use `wxo_bob_agent_analytics.sh` (proceed to Step 3A).
- **Past runs / session history** → use `wxo_bob_session_analytics.sh` (proceed to Step 3B).

If the user mentions a date range, default to **Script B**.
If the user says "test it now" or "check if it works", default to **Script A**.

---

## Step 3A — Single-run analytics (Script A)

Run from `watsonx-orchestrate-adk/` with the virtual environment active.
Recommend opening a **new terminal** — the script polls the agent, streams
Bob's analysis, then exits cleanly on its own.

```bash
cd watsonx-orchestrate-adk && source .venv/bin/activate && \
  bash wxo_bob_agent_analytics.sh
```

**Common variants:**

```bash
# Different agent and message
bash wxo_bob_agent_analytics.sh -n <agent_name> -m "Your test message"

# Export trace only, skip Bob
bash wxo_bob_agent_analytics.sh --trace-only

# Deeper observation fetch for multi-tool agents
bash wxo_bob_agent_analytics.sh --obs-limit 200 --ctx-lines 400

# Extend timeout for slow agents
bash wxo_bob_agent_analytics.sh --poll-timeout 300 --poll-interval 10

# Custom analysis question
bash wxo_bob_agent_analytics.sh -q "Why did the LLM call take over 3 seconds?"
```

**What the script does (execution tree):**

```
wxo_bob_agent_analytics.sh
│
├─ Step 1 ── Resolve agent name → agent ID   (GET /v1/orchestrate/agents)
├─ Step 2 ── Send test message               (POST /v1/orchestrate/runs)
├─ Step 3 ── Poll until run completes        (GET /v1/orchestrate/runs/{id})
│            → captures run_id, thread_id, trace_id, final response
├─ Step 4 ── Wait 5s, export trace           (Langfuse /api/public/traces + observations)
│            → agent-analytics/<agent>/<ts>/trace.json
│            → agent-analytics/<agent>/<ts>/analytics_context.md  (Production-Hardening Signals table
│                                                                   + trace table + JSON excerpt)
└─ Step 5 ── bob run --mode ask "<context+question>"
             → agent-analytics/<agent>/<ts>/BOB_AGENT_ANALYTICS_REPORT.md  (clean GFM + IBM Bob CLI Usage)
```

Each run creates a dedicated folder `watsonx-orchestrate-adk/agent-analytics/<agent_name>/<timestamp>/`.

---

## Step 3B — Session analytics (Script B)

`--from` is required. `--to` defaults to now. Bare `YYYY-MM-DD` dates expand to
`T00:00:00Z` / `T23:59:59Z` automatically. Recommend opening a **new terminal**
— the script fetches traces, streams Bob's analysis, then exits cleanly on its own.

```bash
cd watsonx-orchestrate-adk && source .venv/bin/activate && \
  bash wxo_bob_session_analytics.sh \
    --from <YYYY-MM-DD> \
    --to   <YYYY-MM-DD>
```

**Common variants:**

```bash
# Different agent, two-hour window
bash wxo_bob_session_analytics.sh \
  -n my_agent \
  --from 2026-08-10T08:00:00Z \
  --to   2026-08-10T10:00:00Z

# Export traces only, skip Bob
bash wxo_bob_session_analytics.sh --from 2026-08-10 --trace-only

# Raise all limits for large agents
bash wxo_bob_session_analytics.sh \
  --from 2026-08-10 \
  --obs-limit 200 --ctx-lines 200 --trace-limit 200

# Custom cross-run question
bash wxo_bob_session_analytics.sh \
  --from 2026-08-10 \
  -q "Which runs gave inconsistent answers? What changed between them?"
```

**What the script does (execution tree):**

```
wxo_bob_session_analytics.sh
│
├─ Step 1 ── Query Langfuse traces in [--from, --to]
│            Filter by agent name (input.current_agent)
│            Fetch observations for each matched trace
│            → session_traces_<ts>.json
├─ Step 2 ── Build consolidated context document
│            Production-Hardening Signals (min/avg/max latency across all runs)
│            + run summary table + per-run observation tables + JSON excerpts
│            → session_context_<ts>.md
└─ Step 3 ── bob run --mode ask "<context+question>"
             → BOB_SESSION_ANALYTICS_REPORT_<ts>.md  (clean GFM + IBM Bob CLI Usage)
```

---

## Step 4 — Present the analysis

After `execute_command` completes, read and summarize the report with `read_file`.

**Single-run report (`BOB_AGENT_ANALYTICS_REPORT.md`):**

| Section | What to highlight |
|---|---|
| Run Summary | Agent name, trace ID, total latency, LLM model used |
| Step-by-step Trace | Each observation with type, latency, token counts |
| LLM Call Details | Model, token counts, system prompt in use |
| Tool Calls | Any tools invoked (names, latency, success/failure) |
| LangGraph Flow | Node sequence from trace metadata |
| Production-Hardening Checks | `service.name` set?, `ls_provider` adapter label, LLM/total latency vs thresholds |
| Verdict | Pass/fail per health criterion |
| IBM Bob CLI Usage | Wall-clock time, prompt size, cost note |

**Session report (`BOB_SESSION_ANALYTICS_REPORT_<ts>.md`):**

| Section | What to highlight |
|---|---|
| Session Summary | Time window, total runs, overall success rate |
| Run-by-run Table | Trace ID, duration, status, response snippet per run |
| Behavior Patterns | Consistency, tool usage variation, latency trends |
| Errors or Anomalies | Failed runs, latency outliers, unexpected observations |
| Production-Hardening Checks | `service.name`, `ls_provider`, min/avg/max LLM and total latency across all runs |
| Recommendation | Is the agent behaving correctly and consistently? |
| IBM Bob CLI Usage | Wall-clock time, prompt size, cost note |

Always surface the **Langfuse UI deep-link** from the report header so the user
can click through to inspect raw spans (login: `orchestrate@ibm.com` / `orchestrate`):

```
http://localhost:3010/project/orchestrate-lite/traces/<trace_id>
```

---

## Step 5 — Actionable follow-up loop

After presenting the report, offer concrete next actions based on findings:

- **Latency too high** → re-run with `--obs-limit 200` to inspect every span and
  use `-q "Which span caused the most latency and why?"`.
- **Tool call failed** → read the raw trace JSON with `read_file` on
  `agent-analytics/<agent>/<ts>/trace.json` and inspect the `output` field of the
  failing observation.
- **Inconsistent session responses** → re-run Script B with a wider window and
  `-q "Which runs gave inconsistent answers? What changed between them?"`.
- **Prompt or instruction issue suspected** → read the agent YAML with `read_file`
  on `watsonx-orchestrate-adk/agents/<agent>.yaml` and compare `instructions`
  against the system prompt captured in the trace.
- **Regression after a config change** → run Script B with `--from <before-change>`
  and `--to <after-change>` spanning the change window.
- **`service.name` NOT SET** → advise setting it in the OpenTelemetry SDK resource
  config: `Resource.create({SERVICE_NAME: "wxo-agent-runtime"})`. Without it,
  traces cannot be filtered by service in multi-agent Langfuse dashboards.
- **`ls_provider = openai`** → this is the watsonx-via-OpenAI-adapter label.
  Advise adding a custom `actual_provider: watsonx` span attribute so dashboards
  and cost/reliability alerts correctly attribute traces to watsonx, not OpenAI.

---

## Key options reference

**Script A (`wxo_bob_agent_analytics.sh`):**

| Option | Default | Purpose |
|---|---|---|
| `--agent / -n` | `agent_hello_world` | Agent name to test |
| `--message / -m` | `"Hello, are you working?"` | Test message |
| `--obs-limit N` | `50` | Max observations from Langfuse |
| `--ctx-lines N` | `150` | Max JSON lines sent to Bob |
| `--poll-timeout N` | `120` | Run timeout in seconds |
| `--trace-only` | off | Export trace; skip Bob |
| `--question / -q` | health prompt | Custom question for Bob |

**Script B (`wxo_bob_session_analytics.sh`):**

| Option | Default | Purpose |
|---|---|---|
| `--agent / -n` | `agent_hello_world` | Agent name to filter |
| `--from / -f` | required | Start of time window |
| `--to / -t` | now | End of time window |
| `--trace-limit N` | `100` | Max traces per Langfuse page |
| `--obs-limit N` | `50` | Max observations per trace |
| `--ctx-lines N` | `80` | Max JSON lines per trace to Bob |
| `--trace-only` | off | Export traces; skip Bob |
| `--question / -q` | session health prompt | Custom question for Bob |
