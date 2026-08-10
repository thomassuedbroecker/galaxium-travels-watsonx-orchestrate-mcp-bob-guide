# 6. Inspect Agent Analytics With IBM Bob

This guide shows how to run a test against a `watsonx Orchestrate` agent, export
the **Agent Analytics** observability trace from the local **Langfuse** backend, and
let **IBM Bob** analyse it — all from a single shell command.

The complete pipeline is in
[`watsonx-orchestrate-adk/wxo_bob_agent_analytics.sh`](./watsonx-orchestrate-adk/wxo_bob_agent_analytics.sh).

A real example report from a live run is saved in the project:
[`watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md`](./watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md)

---

## 6.1 How It Works

```
wxo_bob_agent_analytics.sh
│
├─ Step 1 ── Resolve agent ID from the local orchestrate API
├─ Step 2 ── Send a test message → POST /v1/orchestrate/runs
├─ Step 3 ── Poll the run until completed → capture trace_id
├─ Step 4 ── Export trace observations from Langfuse (http://localhost:3010)
└─ Step 5 ── Pass trace to bob run → save BOB_AGENT_ANALYTICS_REPORT_<ts>.md
```

### What is Agent Analytics?

`watsonx Orchestrate` provides LLM observability through a native integration with
[**Langfuse**](https://langfuse.com/) — an open-source analytics platform.
When the Developer Edition server is started with `--with-ibm-telemetry`, it runs
a **local Langfuse container** that records every agent run as a trace. No data
leaves your laptop.

Two local URLs are available after server startup:

| URL | What it is |
|---|---|
| `https://localhost:8765/` | Main watsonx Orchestrate UI (page title: "Agent Analytics") |
| `http://localhost:3010/` | Langfuse API and UI — queried directly by `wxo_bob_agent_analytics.sh` |

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

## 6.3 Verify The Setup

### BOB_API_KEY

`bob run` requires an API key for headless (non-interactive) use. Set it once in
`watsonx-orchestrate-adk/.env`:

```sh
export BOB_API_KEY=<YOUR_BOB_API_KEY>
```

Create the key at **bob.ibm.com → Account → API Keys** (scope: **Inference**).
The `.env_template` file already contains the placeholder — copy and fill it:

```sh
cp watsonx-orchestrate-adk/.env_template watsonx-orchestrate-adk/.env
# then edit .env and set BOB_API_KEY
```

### Service checks

Run these three checks before the analytics pipeline:

```sh
# 1. Langfuse API is healthy
curl -s http://localhost:3010/api/public/health
# expected: {"status":"ok"}

# 2. Active orchestrate environment is 'local'
cd watsonx-orchestrate-adk && source .venv/bin/activate
orchestrate env list
# expected: local (active)

# 3. agent_hello_world is imported
orchestrate agents list
# expected: agent_hello_world listed
```

If any check fails, re-run the start script:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
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

## 6.5 Run The Analytics Pipeline

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_bob_agent_analytics.sh
```

### Live terminal output (verified run 2026-07-31)

```
Environment : local
WXO URL     : http://localhost:4321
Langfuse    : http://localhost:3010
Langfuse    : reachable (HTTP 200)

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

════════════════════════════════════════
  Step 3 — Polling run for completion (timeout: 120s)
════════════════════════════════════════
  ... 3s — status: running
Run status: completed
Trace ID : a86f7ef0f35d7169dddab662259778ff
Response : Hello! Yes, I'm working correctly. I'm ready to assist you with
           any questions or tasks you may have. How can I help you today?

════════════════════════════════════════
  Step 4 — Exporting trace from Langfuse (http://localhost:3010)
════════════════════════════════════════
Waiting 5s for Langfuse ingestion...
Exported: 4 observations → ./agent-analytics/trace_20260731_170044.json
Trace file: ./agent-analytics/trace_20260731_170044.json
Context: 180 lines (4 observations)

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
Report   : ./agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md
```

---

## 6.6 The Trace File

The script exports observations from Langfuse into a structured JSON file at:
`watsonx-orchestrate-adk/agent-analytics/trace_<ts>.json`

The real trace from the verified run shows:

```
LangGraph (CHAIN, 1 644 ms)            ← root span
└── agent (AGENT, 1 577 ms)            ← LangGraph agent node
│   └── invoke_agent (GENERATION, 1 558 ms)  ← LLM call to meta-llama/llama-3-3-70b-instruct
└── answer (CHAIN, 5 ms)               ← final routing node
```

Each `GENERATION` observation contains:

```json
{
  "name": "invoke_agent",
  "type": "GENERATION",
  "model": "meta-llama/llama-3-3-70b-instruct",
  "latency": 1.558,
  "timeToFirstToken": 1.087,
  "input": [
    { "role": "system", "content": "You are a simple test assistant..." },
    { "role": "user",   "content": "Hello, are you working?" }
  ],
  "output": { "role": "assistant", "content": "Hello! Yes, I'm working correctly..." },
  "usage": { "input": 63, "output": 32, "total": 95 }
}
```

---

## 6.7 The Bob Analysis Report

The report is saved to:
`watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_<ts>.md`

A real example from a live run is in the project:
[`agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md`](./watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md)

Every report begins with a metadata header written by the script **before** Bob's
analysis is appended:

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

The **Langfuse UI** link opens the trace directly in the local Langfuse browser UI
so you can visually inspect spans alongside Bob's written analysis.

Bob's analysis follows the metadata header and contains:

| Section | What Bob reports |
|---|---|
| **Run Summary** | Agent name, trace ID, run ID, total latency, LLM used |
| **Step-by-step Trace** | Each observation with type, start time, latency, token counts |
| **LLM Call Details** | Model, system prompt, input/output tokens, time to first token |
| **Tool Calls** | Lists any tools invoked (none for `agent_hello_world`) |
| **LangGraph Flow** | Exact node sequence from the trace metadata |
| **Verdict** | Health check table — pass/fail per criterion |

---

## 6.8 Script Options

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
--trace-only      Export trace only; skip Bob.
--help            Show help and exit.
```

### Usage examples

```sh
# Run with a different agent and message:
bash wxo_bob_agent_analytics.sh -n my_agent -m "What can you do?"

# Export trace only — no Bob analysis:
bash wxo_bob_agent_analytics.sh --trace-only

# Deeper analysis with architecture review mode:
bash wxo_bob_agent_analytics.sh --bob-mode arch-review

# Custom Bob question focused on latency:
bash wxo_bob_agent_analytics.sh \
  -q "Which step took the longest and why?"

# Save report to a specific path:
bash wxo_bob_agent_analytics.sh \
  --export-file ./temp/analytics_$(date +%Y%m%d).md
```

---

## 6.9 All Generated Files

Every run creates timestamped files in `watsonx-orchestrate-adk/agent-analytics/`:

| File | What it contains |
|---|---|
| `trace_<ts>.json` | Full Langfuse trace — all 4 observations with input/output JSON |
| `run_status_<ts>.json` | Raw response from `/v1/orchestrate/runs/{id}` |
| `analytics_context_<ts>.md` | Compact summary piped to Bob (trace table + JSON excerpt) |
| `BOB_AGENT_ANALYTICS_REPORT_<ts>.md` | Bob's structured analysis report |

---

## 6.10 All Artifacts In This Guide

| Artifact | Location | Purpose |
|---|---|---|
| `wxo_bob_agent_analytics.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_bob_agent_analytics.sh) | The automation script |
| `agent_hello_world.yaml` | [`watsonx-orchestrate-adk/agents/`](./watsonx-orchestrate-adk/agents/agent_hello_world.yaml) | Agent under test |
| `trace_20260731_170044.json` | [`agent-analytics/`](./watsonx-orchestrate-adk/agent-analytics/trace_20260731_170044.json) | Real example trace (52 KB, 4 observations) |
| `BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md` | [`agent-analytics/`](./watsonx-orchestrate-adk/agent-analytics/BOB_AGENT_ANALYTICS_REPORT_20260731_170044.md) | Real example Bob report |

---

### [Home](./README.md)
