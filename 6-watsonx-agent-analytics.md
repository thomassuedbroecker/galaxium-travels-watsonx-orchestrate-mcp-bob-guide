# 6. Inspect Agent Analytics With IBM Bob

This guide shows two ways to analyse `watsonx Orchestrate` agent behaviour using
the local **Langfuse** observability backend and **IBM Bob**:

| Script | When to use |
|---|---|
| [`wxo_bob_agent_analytics.sh`](./watsonx-orchestrate-adk/wxo_bob_agent_analytics.sh) | Fire a **new test run**, capture its trace, ask Bob to analyse it |
| [`wxo_bob_session_analytics.sh`](./watsonx-orchestrate-adk/wxo_bob_session_analytics.sh) | Inspect **all past runs** of an agent within a time window — no new run needed |

Both scripts query the local Langfuse API at `http://localhost:3010`, build a
structured context document, and pipe it to `bob run` for AI analysis. The report
is saved as a Markdown file you can read, share, or commit.

---

## 6.1 What Is Agent Analytics?

`watsonx Orchestrate` provides LLM observability through a native integration with
[**Langfuse**](https://langfuse.com/) — an open-source analytics platform.
When the Developer Edition server is started with `--with-ibm-telemetry`, it runs
a **local Langfuse container** that records every agent run as a trace. No data
leaves your laptop.

Two local URLs are available after server startup:

| URL | What it is |
|---|---|
| `https://localhost:8765/` | Main watsonx Orchestrate UI (page title: "Agent Analytics") |
| `http://localhost:3010/` | Langfuse API and UI — queried directly by both scripts |

Reference: [Monitoring your LLMs with Langfuse](https://developer.watson-orchestrate.ibm.com/llm/observability)

---

## 6.2 Prerequisites

> **If you already ran `wxo_local_start.sh`, all prerequisites are satisfied — skip to §6.3.**

| Requirement | How it is satisfied |
|---|---|
| Developer Edition running with telemetry | `wxo_local_start.sh` starts the server with `--with-ibm-telemetry` |
| Langfuse running at `http://localhost:3010/` | Included in `--with-ibm-telemetry` |
| `orchestrate env activate local` done | `wxo_local_start.sh` activates the local environment |
| `agent_hello_world` imported | `wxo_local_start.sh` imports the agent |
| IBM Bob CLI | `npm install -g @ibm/bob-cli` |
| `BOB_API_KEY` | Required for headless `bob run` — set in `.env` (see §6.3) |
| `jq` | `brew install jq` |

---

## 6.3 One-Time Setup

### Step 1 — Copy the env template

```sh
cp watsonx-orchestrate-adk/.env_template watsonx-orchestrate-adk/.env
```

### Step 2 — Set BOB_API_KEY

`bob run` requires an API key for headless (non-interactive) use. Edit
`watsonx-orchestrate-adk/.env` and fill in:

```sh
export BOB_API_KEY=<YOUR_BOB_API_KEY>
```

Create the key at **bob.ibm.com → Account → API Keys** (scope: **Inference**).

### Step 3 — Activate the virtual environment

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
```

### Step 4 — Verify the services

```sh
# Langfuse API is healthy
curl -s http://localhost:3010/api/public/health
# expected: {"status":"ok"}

# Active orchestrate environment is 'local'
orchestrate env list
# expected: local (active)

# agent_hello_world is imported
orchestrate agents list
# expected: agent_hello_world listed
```

If any check fails, re-run the start script:

```sh
bash wxo_local_start.sh
```

---

## 6.4 The Agent Under Test

[`agents/agent_hello_world.yaml`](./watsonx-orchestrate-adk/agents/agent_hello_world.yaml)
is the minimal smoke-test agent imported by `wxo_local_start.sh`:

```yaml
spec_version: v1
kind: native
name: agent_hello_world
description: A minimal smoke-test agent to verify agent creation works.
instructions: >
  You are a simple test assistant. When greeted, respond with a friendly hello
  and confirm you are working correctly.
llm: watsonx/meta-llama/llama-3-3-70b-instruct
style: react_intrinsic
```

---

## 6.5 Script A — Single-Run Analytics (`wxo_bob_agent_analytics.sh`)

Use this script when you want to **trigger a new test message** against the agent,
capture the resulting trace, and immediately ask Bob to analyse it.

### How it works

```
wxo_bob_agent_analytics.sh
│
├─ Step 1 ── Resolve agent name → agent ID  (GET /v1/orchestrate/agents)
├─ Step 2 ── Send test message              (POST /v1/orchestrate/runs)
├─ Step 3 ── Poll until run completes       (GET /v1/orchestrate/runs/{id})
│            → captures run_id, thread_id, trace_id, final response
├─ Step 4 ── Wait 5s, export trace          (Langfuse /api/public/traces + observations)
│            → trace_<ts>.json
│            → analytics_context_<ts>.md   (Production-Hardening Signals + trace table + JSON excerpt)
└─ Step 5 ── bob run --mode ask "<context+question>"
             → BOB_AGENT_ANALYTICS_REPORT_<ts>.md  (includes IBM Bob CLI Usage section)
```

### Step-by-step walkthrough

#### Step 1 — Run the script

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_bob_agent_analytics.sh
```

The script loads `.env` (picks up `BOB_API_KEY`), resolves the agent ID, and
prints the active environment:

```
Environment : local
WXO URL     : http://localhost:4321
Langfuse    : http://localhost:3010
Langfuse    : reachable (HTTP 200)
```

#### Step 2 — Agent is resolved and run is submitted

```
════════════════════════════════════════
  Step 1 — Resolving agent 'agent_hello_world'
════════════════════════════════════════
Agent ID: 3bae183b-8f03-43b6-818e-fc2bddf4f2ba

════════════════════════════════════════
  Step 2 — Sending test message
════════════════════════════════════════
Message: Hello, are you working?
Run ID   : 538f2102-65aa-4ef5-b67b-6d3548d43895
Thread ID: 594019c5-d704-4dbc-85e6-f70993e43f91
```

#### Step 3 — Run is polled until completion

```
════════════════════════════════════════
  Step 3 — Polling run for completion (timeout: 120s, interval: 3s)
════════════════════════════════════════
  ... 3s — status: running
Run status: completed
Trace ID : a86f7ef0f35d7169dddab662259778ff
Response : Hello! Yes, I'm working correctly. I'm ready to assist you with
           any questions or tasks you may have. How can I help you today?
```

#### Step 4 — Trace is exported from Langfuse

```
════════════════════════════════════════
  Step 4 — Exporting trace from Langfuse (http://localhost:3010)
════════════════════════════════════════
Waiting 5s for Langfuse ingestion...
Exported: 4 observations → ./agent-analytics/trace_20260731_170044.json
Trace file: ./agent-analytics/trace_20260731_170044.json
Context: 212 lines (4 observations)
```

The context document now opens with a **Production-Hardening Signals** table computed
directly from the trace JSON before anything is sent to Bob:

```
| Signal        | Value         | Note                                                         |
|---|---|---|
| service.name  | NOT SET       | ⚠ Recommend setting to meaningful value (e.g. wxo-agent-runtime) |
| ls_provider   | openai        | ⚠ watsonx-via-OpenAI-adapter label — account for this in dashboard/alert filters |
| LLM latency   | 2400 ms       | ✓                                                            |
| Total trace   | 3800 ms       | ✓                                                            |
```

The four observations represent the LangGraph execution tree:

```
LangGraph (CHAIN, 1 644 ms)                    ← root span
└── agent (AGENT, 1 577 ms)                    ← LangGraph agent node
    └── invoke_agent (GENERATION, 1 558 ms)    ← LLM call
└── answer (CHAIN, 5 ms)                       ← final routing node
```

#### Step 5 — Bob analyses the trace

```
════════════════════════════════════════
  Step 5 — IBM Bob CLI analysis (mode: ask)
════════════════════════════════════════
Building prompt → bob run --mode "ask" "<context+question>"
Output → terminal + ./agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md

[Bob analysis streams here...]

════════════════════════════════════════
Agent    : agent_hello_world
Trace ID : a86f7ef0f35d7169dddab662259778ff
Trace    : ./agent-analytics/trace_20260731_170044.json
Langfuse : http://localhost:3010
Bob mode : ask
Bob time : 18 s
Report   : ./agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md
```

### The report

Every report begins with a metadata header written before Bob's analysis:

```markdown
## Run Metadata

| Field | Value |
|---|---|
| Agent | agent_hello_world |
| Trace ID | a86f7ef0f35d7169dddab662259778ff |
| Run ID | 538f2102-65aa-4ef5-b67b-6d3548d43895 |
| Thread ID | 594019c5-d704-4dbc-85e6-f70993e43f91 |
| Bob mode | ask |
| Generated | 2026-07-31 17:00:44 |
| Trace file | ./agent-analytics/trace_20260731_170044.json |
| Langfuse | http://localhost:3010 |
| Langfuse UI | http://localhost:3010/project/orchestrate-lite/traces/a86f7ef0f35d7169dddab662259778ff |
```

The **Langfuse UI** link opens the trace directly in the browser so you can
visually inspect spans alongside Bob's written analysis.

Bob's analysis contains:

| Section | What Bob reports |
|---|---|
| **Run Summary** | Agent name, trace ID, run ID, total latency, LLM used |
| **Step-by-step Trace** | Each observation with type, start time, latency, token counts |
| **LLM Call Details** | Model, system prompt, input/output tokens, time to first token |
| **Tool Calls** | Lists any tools invoked (none for `agent_hello_world`) |
| **LangGraph Flow** | Exact node sequence from the trace metadata |
| **Production-Hardening Checks** | `service.name` presence, `ls_provider` adapter label, LLM and total latency vs thresholds (verified output below) |
| **Verdict** | Health check table — pass/fail per criterion |
| **IBM Bob CLI Usage** | Bob mode, wall-clock time, prompt size (chars), cost note |

The **Production-Hardening Checks** section is produced by Bob from the signals table
in the context document. Verified output from a real run:

```markdown
### 5. Production-Hardening Checks

#### a. service.name — ⚠️ NOT SET

The resourceAttributes block shows telemetry.sdk.* entries but service.name is absent.
This means all traces from this deployment appear as an unnamed service in Langfuse /
OpenTelemetry backends, making it impossible to filter or alert by service in a
multi-agent environment.

Recommendation: Set service.name at the OpenTelemetry SDK init level, e.g.:

  from opentelemetry.sdk.resources import Resource, SERVICE_NAME
  resource = Resource.create({SERVICE_NAME: "wxo-agent-runtime"})

#### b. ls_provider = "openai" — ⚠️ Adapter Label Mismatch

The response_metadata shows:

  "model_provider": "openai",
  "actual_model": "watsonx/meta-llama/llama-3-3-70b-instruct"

The LangSmith/Langfuse ls_provider tag resolves to openai because the watsonx endpoint
is accessed via the OpenAI-compatible adapter. Any dashboard widgets or alerts filtering
on ls_provider = "watsonx" will silently miss these traces.

Recommendation: Add a custom tag (e.g. actual_provider: watsonx) at trace creation time
so dashboards can correctly segment cost, latency, and error-rate metrics by the true
provider.
```

A real example report from a verified run is in the project:
[`agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md`](./watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md)

### Generated files

Every run creates timestamped files in `watsonx-orchestrate-adk/agent-analytics/`:

| File | What it contains |
|---|---|
| `trace_<ts>.json` | Full Langfuse trace — all observations with input/output JSON |
| `run_status_<ts>.json` | Raw response from `/v1/orchestrate/runs/{id}` |
| `analytics_context_<ts>.md` | Compact context sent to Bob — includes Production-Hardening Signals table, trace table, JSON excerpt |
| `BOB_AGENT_ANALYTICS_REPORT_<ts>.md` | Bob's structured analysis report, including IBM Bob CLI Usage section |

### Options

```
--agent      -n   Agent name (snake_case).    Default: agent_hello_world
--message    -m   Test message to send.       Default: "Hello, are you working?"
--output-dir -o   Directory for all output.   Default: ./agent-analytics
--question   -q   Custom question for Bob.
--bob-mode        Bob run mode.               Default: ask
--export-file     Custom path for Bob report.
--env-file   -e   Path to .env file.          Default: .env
--langfuse-url    Langfuse base URL.          Default: http://localhost:3010
--langfuse-pk     Langfuse public key.        Default: pk-lf-orchestrate
--langfuse-sk     Langfuse secret key.        Default: sk-lf-orchestrate
--poll-timeout N  Seconds before run times out.           Default: 120
--poll-interval N Seconds between status polls.           Default: 3
--obs-limit N     Max observations fetched from Langfuse. Default: 50
--ctx-lines N     Max JSON lines sent to Bob context.     Default: 150
--trace-only      Export trace only; skip Bob.
--help            Show help and exit.
```

### Usage examples

Each example states its **objective** — what you are trying to find out — so you
can pick the right combination of flags for your situation.

```sh
# Objective: verify the default agent responds correctly right now.
# Sends the default greeting message and asks Bob to confirm the
# agent completed successfully and the LLM answered as expected.
bash wxo_bob_agent_analytics.sh

# Objective: test a specific agent with a targeted question and inspect
# whether it understands its own capabilities before a demo.
bash wxo_bob_agent_analytics.sh \
  -n my_agent \
  -m "What can you do?" \
  -q "Did the agent correctly describe its capabilities? Were all tool descriptions returned?"

# Objective: capture the raw execution trace for offline review or to
# attach to a bug report, without triggering a Bob analysis run.
bash wxo_bob_agent_analytics.sh --trace-only

# Objective: diagnose why a known-slow agent times out under default
# settings — extend the poll window and reduce log noise.
bash wxo_bob_agent_analytics.sh \
  --poll-timeout 300 \
  --poll-interval 10 \
  -q "Which span accounted for the most latency, and is that expected?"

# Objective: inspect every step of a multi-tool agent in full detail —
# increase observation and context limits so no span is truncated.
bash wxo_bob_agent_analytics.sh \
  --obs-limit 200 \
  --ctx-lines 400 \
  -q "List every tool call made, its input, output, and whether it succeeded."

# Objective: save the Bob report to a dated archive path for a
# nightly CI job or scheduled health check.
bash wxo_bob_agent_analytics.sh \
  --export-file ./temp/analytics_$(date +%Y%m%d).md
```

---

## 6.6 Script B — Session Analytics (`wxo_bob_session_analytics.sh`)

Use this script when you want to **inspect how an agent behaved across multiple
past runs** within a time window — without triggering any new run. It queries
Langfuse history directly.

### How it works

```
wxo_bob_session_analytics.sh
│
├─ Step 1 ── Query Langfuse traces in [--from, --to]
│            Filter by agent name (input.current_agent)
│            Fetch observations for each matched trace
│            → session_traces_<ts>.json
│
├─ Step 2 ── Build consolidated context document
│            Run summary table + per-run observation tables + JSON excerpts
│            → session_context_<ts>.md
│
└─ Step 3 ── bob run --mode ask "<context+question>"
             → BOB_SESSION_ANALYTICS_REPORT_<ts>.md
```

### Step-by-step walkthrough

#### Step 1 — Run the script with a time window

`--from` is required. `--to` defaults to now. Bare `YYYY-MM-DD` dates are
automatically expanded to `T00:00:00Z` / `T23:59:59Z`.

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_bob_session_analytics.sh \
  --from 2026-08-10 \
  --to   2026-08-11
```

The script verifies Langfuse reachability and prints the resolved window:

```
Agent       : agent_hello_world
From        : 2026-08-10T00:00:00Z
To          : 2026-08-11T23:59:59Z
Langfuse    : http://localhost:3010 (reachable)
```

#### Step 2 — Traces are fetched and filtered

```
════════════════════════════════════════
  Step 1 — Fetching traces for 'agent_hello_world' [2026-08-10T00:00:00Z → 2026-08-11T23:59:59Z]
════════════════════════════════════════
Langfuse returned 3 traces in window (total in project: 12); 3 match agent 'agent_hello_world'
  trace 9eff6c5407b9… — 4 observations
  trace a12f3d8801c2… — 4 observations
  trace b99e20ff4401… — 6 observations
Saved: 3 traces → ./agent-analytics/session_traces_20260810_110000.json
Traces matched: 3
```

Langfuse is queried with `fromTimestamp` / `toTimestamp` and `name=LangGraph`
(all wxO traces use this name). Client-side filtering then matches
`input.current_agent` to the `--agent` value.

#### Step 3 — Context document is built

```
════════════════════════════════════════
  Step 2 — Building session context document
════════════════════════════════════════
Context: 287 lines (3 runs)
Context file: ./agent-analytics/session_context_20260810_110000.md
```

The context document contains:

- A **run summary table** (trace ID, timestamp, duration, observation count, response snippet)
- A **per-run observations table** for each trace
- A **JSON excerpt** (first `--ctx-lines` lines) for each trace

#### Step 4 — Bob analyses all runs together

```
════════════════════════════════════════
  Step 3 — IBM Bob CLI analysis (mode: ask)
════════════════════════════════════════
Building prompt → bob run --mode "ask" "<context+question>"
Output → terminal + ./agent-analytics/BOB_SESSION_ANALYTICS_REPORT_20260810_110000.md

[Bob analysis streams here...]

════════════════════════════════════════
Agent        : agent_hello_world
Window       : 2026-08-10T00:00:00Z → 2026-08-11T23:59:59Z
Runs         : 3
Traces file  : ./agent-analytics/session_traces_20260810_110000.json
Langfuse     : http://localhost:3010
Bob mode     : ask
Report       : ./agent-analytics/BOB_SESSION_ANALYTICS_REPORT_20260810_110000.md
```

### The report

Every report begins with a session metadata header:

```markdown
## Session Metadata

| Field | Value |
|---|---|
| Agent | agent_hello_world |
| From | 2026-08-10T00:00:00Z |
| To | 2026-08-11T23:59:59Z |
| Runs found | 3 |
| Bob mode | ask |
| Generated | 2026-08-10 11:00:00 |
| Traces file | ./agent-analytics/session_traces_20260810_110000.json |
| Langfuse | http://localhost:3010 |
```

Bob's analysis contains:

| Section | What Bob reports |
|---|---|
| **Session Summary** | Agent name, time window, total runs, overall success rate |
| **Run-by-run Table** | Trace ID, timestamp, duration, status, response snippet per run |
| **Behaviour Patterns** | Consistency of responses, tool usage variation, latency trends |
| **Errors or Anomalies** | Failed runs, unexpected observations, latency outliers |
| **Production-Hardening Checks** | `service.name` presence, `ls_provider` label discrepancy, min/avg/max LLM and total latency across all runs, flags for threshold breaches |
| **Recommendation** | Is the agent behaving correctly and consistently? |
| **IBM Bob CLI Usage** | Bob mode, wall-clock time, prompt size (chars), cost note |

### Generated files

Every run creates timestamped files in `watsonx-orchestrate-adk/agent-analytics/`:

| File | What it contains |
|---|---|
| `session_traces_<ts>.json` | All matched traces with observations |
| `session_context_<ts>.md` | Consolidated context — includes Production-Hardening Signals table (min/avg/max latency across all runs) |
| `BOB_SESSION_ANALYTICS_REPORT_<ts>.md` | Bob's cross-run analysis report, including IBM Bob CLI Usage section |

### Options

```
--agent      -n   Agent name to filter on.    Default: agent_hello_world
--from       -f   Start of time window (ISO-8601 or YYYY-MM-DD). Required.
--to         -t   End of time window.         Default: now
--output-dir -o   Directory for all output.   Default: ./agent-analytics
--question   -q   Custom question for Bob.
--bob-mode        Bob run mode.               Default: ask
--export-file     Custom path for Bob report.
--env-file   -e   Path to .env file.          Default: .env
--langfuse-url    Langfuse base URL.          Default: http://localhost:3010
--langfuse-pk     Langfuse public key.        Default: pk-lf-orchestrate
--langfuse-sk     Langfuse secret key.        Default: sk-lf-orchestrate
--trace-limit N   Max traces fetched per page.              Default: 100
--obs-limit N     Max observations fetched per trace.       Default: 50
--ctx-lines N     Max JSON lines per trace in Bob context.  Default: 80
--trace-only      Export traces only; skip Bob.
--help            Show help and exit.
```

### Usage examples

Each example states its **objective** — what you are trying to find out — so you
can pick the right combination of flags for your situation.

```sh
# Objective: review all runs of the default agent across a full working day
# to confirm it behaved consistently and completed without errors.
bash wxo_bob_session_analytics.sh \
  --from 2026-08-10 \
  --to   2026-08-10

# Objective: investigate whether a specific agent produced inconsistent
# answers during a two-hour window after a prompt change was deployed.
bash wxo_bob_session_analytics.sh \
  -n my_agent \
  --from 2026-08-10T08:00:00Z \
  --to   2026-08-10T10:00:00Z \
  -q "Did the agent give consistent answers across all runs? If not, which runs differed and why?"

# Objective: collect the raw session traces for a date range to attach
# to a support ticket or share with another team, without a Bob analysis.
bash wxo_bob_session_analytics.sh \
  --from 2026-08-10 \
  --trace-only

# Objective: identify latency outliers across runs on a given day —
# find which runs were slowest and which span caused the delay.
bash wxo_bob_session_analytics.sh \
  --from 2026-08-10 \
  -q "Which runs had the highest total latency? Which observation span was the bottleneck in each case?"

# Objective: perform a full inspection of a complex multi-tool agent
# with many observations per run — raise all limits to avoid truncation.
bash wxo_bob_session_analytics.sh \
  --from 2026-08-10 \
  --obs-limit 200 \
  --ctx-lines 200 \
  --trace-limit 200 \
  -q "List every tool call across all runs, its success status, and any errors in the output field."
```

---

## 6.7 Choosing The Right Script

| Situation | Use |
|---|---|
| "Does the agent respond correctly right now?" | `wxo_bob_agent_analytics.sh` |
| "Did the agent behave correctly this morning?" | `wxo_bob_session_analytics.sh` |
| "Compare multiple runs after a config change" | `wxo_bob_session_analytics.sh` |
| "Debug a single failing run by trace ID" | `wxo_bob_agent_analytics.sh --trace-only` then inspect `trace_<ts>.json` |
| "Check latency trends over a day" | `wxo_bob_session_analytics.sh --from <day>` |

---

## 6.8 All Artifacts In This Guide

| Artifact | Location | Purpose |
|---|---|---|
| `wxo_bob_agent_analytics.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_bob_agent_analytics.sh) | Single-run: fire a test, capture trace, ask Bob |
| `wxo_bob_session_analytics.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_bob_session_analytics.sh) | Session: query past runs by time window, ask Bob |
| `agent_hello_world.yaml` | [`watsonx-orchestrate-adk/agents/`](./watsonx-orchestrate-adk/agents/agent_hello_world.yaml) | Agent under test |
| `trace_20260731_170044.json` | [`agent-analytics/`](./watsonx-orchestrate-adk/agent-analytics/trace_20260731_170044.json) | Real example single-run trace (4 observations) |
| `BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md` | [`agent-analytics/`](./watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md) | Real example single-run Bob report |

---

### [Home](./README.md)
