# 7. Inspect Agent Analytics With IBM Bob

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

## 7.1 What Is Agent Analytics?

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

## 7.2 Prerequisites

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

## 7.3 One-Time Setup

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

## 7.4 The Agent Under Test

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

> **Why this agent?** `agent_hello_world` has no tools, no knowledge base, no MCP
> connections. If a run fails, the fault is in the LLM call path or the agent
> runtime — nowhere else. It is the minimal baseline before testing complex agents.

---

## 7.5 Script A — Single-Run Analytics (`wxo_bob_agent_analytics.sh`)

### 7.5.1 Test Scenario Definition

Before running the script, define what you are testing and what "success" means.
This makes the Bob question precise and the result verifiable.

| Field | Value |
|---|---|
| **Agent under test** | `agent_hello_world` |
| **Test message** | `"Hello, are you working?"` |
| **Objective** | Confirm the agent receives the message, calls the LLM, and returns a coherent response — with no errors in the trace |
| **Success criteria** | Run status = `completed`; all trace observations = `OK`; total latency < 15,000 ms; agent response contains an affirmative answer |
| **Anomaly watch list** | Any non-`OK` observation; any tool call present (there should be none); `service.name` missing; `ls_provider` value; LLM latency > 10,000 ms |
| **Script** | `wxo_bob_agent_analytics.sh` — triggers a **new live run** every time, nothing is reused |
| **Bob question focus** | *"Did the integration work? Are there any errors or anomalies? Is the agent behaving as expected?"* |

### 7.5.2 Worked Exercise — Does the Integration Work?

#### Step 1 — Confirm prerequisites

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate

# Langfuse must be healthy
curl -s http://localhost:3010/api/public/health
# Expected: {"status":"ok"}

# Active environment must be local
orchestrate env list
# Expected: local  (active)

# The agent must be imported
orchestrate agents list
# Expected: agent_hello_world listed
```

If any check fails, re-run the start script:

```sh
bash wxo_local_start.sh
```

#### Step 2 — Run the script

Every execution triggers a **new run** against the live agent, exports a fresh
trace from Langfuse, and writes new timestamped output files:

> **Tip — recommended: open a new terminal for this step.**
> The script polls the agent run, streams Bob's analysis, and then exits cleanly
> on its own. Running it in a dedicated terminal keeps your main working shell
> uncluttered and lets you interact with the watsonx Orchestrate UI or other
> tools in parallel without the terminal output interfering.

```sh
bash wxo_bob_agent_analytics.sh \
  -n agent_hello_world \
  -m "Hello, are you working?" \
  -q "Did the integration work? Are there any errors or anomalies in the trace? \
Is the agent behaving as expected for a no-tool hello-world agent?"
```

> **What the script does — step by step:**
> 1. Loads `.env` → reads `BOB_API_KEY`, prints environment summary
> 2. `GET /v1/orchestrate/agents` → resolves `agent_hello_world` to its agent ID
> 3. `POST /v1/orchestrate/runs` → sends the test message, captures `run_id` + `thread_id`
> 4. `GET /v1/orchestrate/runs/{run_id}` every 3 s → polls until `status: completed` (or 120 s timeout)
> 5. Waits 5 s for Langfuse ingestion, fetches the trace + observations from `http://localhost:3010`
> 6. Writes `trace_<ts>.json` and builds `analytics_context_<ts>.md` — includes Production-Hardening Signals table
> 7. Passes context + question to `bob run --mode ask`
> 8. Writes `BOB_AGENT_ANALYTICS_REPORT_<ts>.md` to `./agent-analytics/`

#### Step 3 — Follow the terminal output

```
Environment : local
WXO URL     : http://localhost:4321
Langfuse    : http://localhost:3010
Langfuse    : reachable (HTTP 200)

════════════════════════════════════════
  Step 1 — Resolving agent 'agent_hello_world'
════════════════════════════════════════
Agent ID: <your-agent-id>

════════════════════════════════════════
  Step 2 — Sending test message
════════════════════════════════════════
Message  : Hello, are you working?
Run ID   : <run-id>
Thread ID: <thread-id>

════════════════════════════════════════
  Step 3 — Polling run (timeout: 120s, interval: 3s)
════════════════════════════════════════
  ... 3s — status: running
Run status: completed
Trace ID : <trace-id>
Response : Hello! Yes, I'm working correctly...

════════════════════════════════════════
  Step 4 — Exporting trace from Langfuse
════════════════════════════════════════
Waiting 5s for Langfuse ingestion...
Exported: 4 observations → ./agent-analytics/trace_<ts>.json

════════════════════════════════════════
  Step 5 — IBM Bob CLI analysis (mode: ask)
════════════════════════════════════════
[Bob streams analysis here...]

════════════════════════════════════════
Agent    : agent_hello_world
Trace ID : <trace-id>
Report   : ./agent-analytics/BOB_AGENT_ANALYTICS_REPORT_<ts>.md
```

Every run produces new `<ts>` values. No previous run's files are overwritten.

#### Step 4 — Read the report

```sh
# Open the newest report
cat agent-analytics/$(ls agent-analytics/ | grep BOB_AGENT | sort | tail -1)
```

Or open `./agent-analytics/` in your file browser and open the newest
`BOB_AGENT_ANALYTICS_REPORT_*.md`.

#### Step 5 — Verify against the scenario definition

Check every item from the scenario (§7.5.1) against what Bob reports:

| Scenario check | Where to look in the report | Pass condition |
|---|---|---|
| Run status | Section "1. Run Summary" → Overall Status | `✅ Completed successfully` |
| All observations OK | Section "2. Step-by-Step Trace" → Status column | All rows `✅ OK` |
| No errors | Section "4. Errors or Anomalies" | `No errors detected` |
| No tool calls | Section "3. Tool Calls Detected" | `None` |
| Total latency | Section "2." → LangGraph duration | < 15,000 ms |
| LLM latency | Section "2." → `invoke_agent` duration | < 10,000 ms |
| Agent response | Section "1." → response text | Affirmative reply |
| `service.name` | Section "5a." | Missing is expected; note it for production |
| `ls_provider` | Section "5b." | `openai` is expected — watsonx-via-OpenAI-adapter |

> **The two ⚠️ anomalies are instrumentation gaps, not integration failures.**
> `service.name` not set and `ls_provider = openai` appear in every fresh run of
> the Developer Edition. Section "5. Production-Hardening Checks" in the report
> explains both and gives the exact code to fix them.

#### Step 6 — Open the Langfuse trace in the browser

The `<trace-id>` is printed in the terminal summary and in the report header.
Open it directly:

```
http://localhost:3010/project/orchestrate-lite/traces/<trace-id>
```

#### Expected LangGraph execution tree

For a `react_intrinsic`-style agent with no tools, expect exactly 4 observations:

```
LangGraph   (CHAIN,      ~4,000–5,000 ms)   ← root span
└── agent   (AGENT,      ~3,500–4,500 ms)   ← LangGraph agent node
    └── invoke_agent  (GENERATION, ~1,500–3,000 ms)  ← LLM call
└── answer  (CHAIN,      ~50–200 ms)         ← final output marshalling
```

If you see more observations or a different tree shape, the agent was routed through
additional nodes — investigate with `--obs-limit 200` (see §7.5.3).

### 7.5.3 How it works (pipeline detail)

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

### 7.5.4 Reference — Report Structure, Generated Files, and Options

#### Report structure

Every report begins with a metadata header:

```markdown
## Run Metadata

| Field | Value |
|---|---|
| Agent | <agent_name> |
| Trace ID | <langfuse_trace_id> |
| Run ID | <wxo_run_id> |
| Thread ID | <wxo_thread_id> |
| Bob mode | ask |
| Generated | <timestamp> |
| Trace file | ./agent-analytics/trace_<ts>.json |
| Langfuse | http://localhost:3010 |
| Langfuse UI | http://localhost:3010/project/orchestrate-lite/traces/<trace_id> |
```

Bob's analysis typically contains these sections (content depends on the agent and
what Bob detects in the trace):

| Section | What Bob reports |
|---|---|
| **Run Summary** | Agent name, trace ID, run ID, total latency, LLM used |
| **Step-by-step Trace** | Each observation with type, start time, latency, token counts |
| **LLM Call Details** | Model, system prompt, input/output tokens, time to first token |
| **Tool Calls** | Lists any tools invoked |
| **LangGraph Flow** | Exact node sequence from the trace metadata |
| **Production-Hardening Checks** | `service.name` presence, `ls_provider` adapter label, LLM and total latency vs thresholds |
| **Verdict** | Health check table — pass/fail per criterion |
| **IBM Bob CLI Usage** | Bob mode, wall-clock time, prompt size (chars), cost note |

#### Generated files

Every run creates timestamped files in `watsonx-orchestrate-adk/agent-analytics/`:

| File | What it contains |
|---|---|
| `trace_<ts>.json` | Full Langfuse trace — all observations with input/output JSON |
| `run_status_<ts>.json` | Raw response from `/v1/orchestrate/runs/{id}` |
| `analytics_context_<ts>.md` | Compact context sent to Bob — includes Production-Hardening Signals table, trace table, JSON excerpt |
| `BOB_AGENT_ANALYTICS_REPORT_<ts>.md` | Bob's structured analysis report, including IBM Bob CLI Usage section |

#### Example files from a real run

The project includes verified example output from a real `agent_hello_world` run under
[`agent-analytics/examples/`](./watsonx-orchestrate-adk/agent-analytics/examples/):

| File | Description |
|---|---|
| [`BOB_AGENT_ANALYTICS_REPORT_20260810_175311.md`](./watsonx-orchestrate-adk/agent-analytics/examples/BOB_AGENT_ANALYTICS_REPORT_20260810_175311.md) | Clean GFM report — metadata header + Bob's full analysis + IBM Bob CLI Usage |
| [`analytics_context_20260810_175311.md`](./watsonx-orchestrate-adk/agent-analytics/examples/analytics_context_20260810_175311.md) | Context document sent to Bob — Production-Hardening Signals + trace table + JSON |
| [`trace_20260810_175311.json`](./watsonx-orchestrate-adk/agent-analytics/examples/trace_20260810_175311.json) | Full Langfuse trace export (observations + metadata) |
| [`run_status_20260810_175311.json`](./watsonx-orchestrate-adk/agent-analytics/examples/run_status_20260810_175311.json) | Raw run status from `/v1/orchestrate/runs/{id}` |

#### All options for `wxo_bob_agent_analytics.sh`

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

#### Usage examples

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

## 7.6 Script B — Session Analytics (`wxo_bob_session_analytics.sh`)

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

> **Tip — recommended: open a new terminal for this step.**
> The script fetches all traces, builds the context document, streams Bob's
> analysis, and then exits cleanly on its own — no `Ctrl-C` required. Running
> it in a dedicated terminal keeps your main working shell uncluttered.

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

## 7.7 Choosing The Right Script

| Situation | Use |
|---|---|
| "Does the agent respond correctly right now?" | `wxo_bob_agent_analytics.sh` |
| "Did the agent behave correctly this morning?" | `wxo_bob_session_analytics.sh` |
| "Compare multiple runs after a config change" | `wxo_bob_session_analytics.sh` |
| "Debug a single failing run by trace ID" | `wxo_bob_agent_analytics.sh --trace-only` then inspect `trace_<ts>.json` |
| "Check latency trends over a day" | `wxo_bob_session_analytics.sh --from <day>` |

---

## 7.8 Verify Traces in the Langfuse UI

After a script run you can log in to the local Langfuse UI and inspect the raw
trace yourself — without reading any JSON.

### 7.8.1 Langfuse Project Reference

When the Developer Edition starts with `--with-ibm-telemetry` it provisions a
local Langfuse instance and seeds it with:

| Item | Value |
|---|---|
| **Organization** | IBM |
| **Project** | Watsonx Orchestrate Lite Project |
| **Project ID (URL slug)** | `orchestrate-lite` |
| **Public key** | `pk-lf-orchestrate` |
| **Secret key** | `sk-lf-orchestrate` |

The analytics scripts use `pk-lf-orchestrate` / `sk-lf-orchestrate` — those keys
are **bound to the `orchestrate-lite` project**. Every agent run is recorded there.

### 7.8.2 Why a Second Organisation Appears (and How to Prevent It)

The `docker-compose.yml` seeds the Langfuse user with:

```yaml
LANGFUSE_INIT_USER_EMAIL: ${LANGFUSE_EMAIL}
LANGFUSE_DEFAULT_USER_EMAIL: ${LANGFUSE_EMAIL}
```

If `LANGFUSE_EMAIL` is **missing from `.env`**, it expands to an empty string.
Langfuse seeds the `orchestrate-lite` project and user with no email. When you
then log in to the UI with `orchestrate@ibm.com`, Langfuse cannot match that
address to the existing empty-email account and **auto-creates a brand-new personal
organisation** (`102b61a7-...` or similar UUID). Agent traces still go to
`orchestrate-lite` (the API key is correct), but the UI user is logged into the
wrong org and sees 0 traces there.

**Fix:** ensure `LANGFUSE_EMAIL=orchestrate@ibm.com` is set in `.env` **before**
starting the server. It is already present in `.env_template` — copy it if you
have not done so.

```sh
# Verify it is set
grep LANGFUSE_EMAIL watsonx-orchestrate-adk/.env
# Expected: export LANGFUSE_EMAIL=orchestrate@ibm.com
```

If you already started the server without it, run a full reset so the seed
re-runs with the correct email:

```sh
cd watsonx-orchestrate-adk
orchestrate server reset
# then restart with wxo_local_start.sh
```

After a clean start with `LANGFUSE_EMAIL` set, only the **IBM** organisation will
exist in the UI and the login `orchestrate@ibm.com` maps directly to the
`Watsonx Orchestrate Lite Project`.

### 7.8.3 Log In and Navigate to the Project

1. Open `http://localhost:3010` in your browser.
2. Log in with:

   | Field | Value |
   |---|---|
   | **Email** | `orchestrate@ibm.com` |
   | **Password** | `LANGFUSE_PASSWORD` from your `.env` (default: `orchestrate`) |

3. On the **Organizations** page click **"Go to project"** under the **IBM**
   organisation to open the **Watsonx Orchestrate Lite Project**.
4. In the left sidebar click **Traces**.

### 7.8.4 Find and Open a Trace

**Option A — deep link from the analytics report**

Every `BOB_AGENT_ANALYTICS_REPORT_*.md` contains a direct URL in its metadata
header:

```
| Langfuse UI | http://localhost:3010/project/orchestrate-lite/traces/<trace_id> |
```

Paste it into your browser to land directly on that trace.

**Option B — find by timestamp**

In the Traces list find the row whose **Timestamp** matches when you ran the
script and click it.

### 7.8.5 What to Look For on the Trace Detail Page

The trace detail page shows the **LangGraph execution tree** as a timeline of
spans. For `agent_hello_world` (no tools) expect exactly four spans:

| Span | Type | What it represents |
|---|---|---|
| `LangGraph` | CHAIN | Root span — full end-to-end duration |
| `agent` | AGENT | LangGraph agent node |
| `invoke_agent` | GENERATION | LLM call — model, token counts, system prompt |
| `answer` | CHAIN | Final output marshalling |

Click any span to expand its **Input / Output**, **Metadata** (`service.name`,
`ls_provider`, model), and **Latency**.

> **`ls_provider = openai` is expected** — this is the watsonx-via-OpenAI-adapter
> label. It does not mean the agent called OpenAI.

### 7.8.6 Cross-Check with the Analytics Report

The `Trace ID` in the terminal output and in the report header identifies the
same trace in both places:

```
# Terminal / report header:
Trace ID : e585e71777219b7f91a0239a23005f9c

# Langfuse UI direct link:
http://localhost:3010/project/orchestrate-lite/traces/e585e71777219b7f91a0239a23005f9c
```

If the trace is not visible immediately, wait 10–15 seconds and refresh —
Langfuse ingestion has a small delay.

---

## 7.9 All Artifacts In This Guide

| Artifact | Location | Purpose |
|---|---|---|
| `wxo_bob_agent_analytics.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_bob_agent_analytics.sh) | Single-run: fire a test, capture trace, ask Bob |
| `wxo_bob_session_analytics.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_bob_session_analytics.sh) | Session: query past runs by time window, ask Bob |
| `agent_hello_world.yaml` | [`watsonx-orchestrate-adk/agents/`](./watsonx-orchestrate-adk/agents/agent_hello_world.yaml) | Agent under test |
| `trace_20260731_170044.json` | [`agent-analytics/`](./watsonx-orchestrate-adk/agent-analytics/trace_20260731_170044.json) | Real example single-run trace (4 observations) |
| `BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md` | [`agent-analytics/`](./watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md) | Real example single-run Bob report |

---

### [Home](./README.md)
