---
name: wxo-log-inspector
description: >
  Use when the user wants to inspect, analyse, or understand watsonx Orchestrate
  Developer Edition server logs. Runs the full bash pipeline in the terminal —
  capture logs, pre-analyse with bash, then invoke the Bob CLI directly to reason
  over the generated report. Trigger phrases: "inspect server logs",
  "check wxo logs", "analyse orchestrate logs", "server log health",
  "what errors are in the logs", "run wxo_bob_inspect.sh".
metadata:
  disable-model-invocation: false
---

# wxo-log-inspector

Inspect watsonx Orchestrate Developer Edition server logs by running a bash
pipeline that ends with the **Bob CLI invoked from the terminal**.

## Architecture

```
Terminal
  │
  └─ bash wxo_bob_inspect.sh
        │
        ├─ Step 1  (optional) wxo_server_log_inspector.sh
        │          limactl → docker logs --follow per container → *.log files
        │
        ├─ Step 2  wxo_server_log_analyze.sh
        │          reads *.log files → ANALYSIS_REPORT.md
        │
        └─ Step 3  cat ANALYSIS_REPORT.md | bob --chat-mode ask \
                       --hide-intermediary-output \
                       --approval-mode yolo \
                       -p "<question>"
```

Bob CLI receives the pre-built Markdown report on **stdin** via the pipe and
reasons over it. No watsonx Orchestrate agent. No tool imports. No Lima VM access
from Bob's side.

---

## Step 1 — Verify prerequisites

Use `execute_command` to run:

```bash
which bob && bob --version 2>&1 | head -3
which jq
ls watsonx-orchestrate-adk/server-logs/ 2>/dev/null | grep -E '^[0-9]{8}_[0-9]{6}$' | sort
```

Confirm:
- `bob` is on PATH (`/Users/.../.nvm/.../bob`)
- `jq` is available
- At least one session folder exists (format `YYYYMMDD_HHMMSS`)

If no sessions exist, the user must run `wxo_server_log_inspector.sh` first (Step 2).

---

## Step 2 — Capture logs (only if no session exists or user wants fresh data)

Ask the user with `ask_followup_question`:
> "Do you want to capture fresh logs, or analyse the most-recent existing session?"

**Fresh capture (timed — runs in background, stops automatically):**

```bash
cd watsonx-orchestrate-adk && source .venv/bin/activate && \
  bash wxo_bob_inspect.sh --capture --capture-seconds 30
```

This starts `wxo_server_log_inspector.sh` in the background, waits 30 seconds,
kills it, then continues automatically to Steps 3 and 4.

**Existing session (skip capture):**

```bash
cd watsonx-orchestrate-adk && source .venv/bin/activate && \
  bash wxo_bob_inspect.sh
```

---

## Step 3 — Run the full pipeline

Use `execute_command` to run the script. It executes all three steps and ends
with Bob CLI producing the analysis in the terminal:

```bash
cd watsonx-orchestrate-adk && source .venv/bin/activate && bash wxo_bob_inspect.sh
```

To change the Bob mode:

```bash
bash wxo_bob_inspect.sh --mode arch-review
```

To ask a specific question:

```bash
bash wxo_bob_inspect.sh -q "Which containers had Redis or database connection errors?"
```

---

## Step 4 — Present Bob's output

After `execute_command` completes, the final output from the `bob` invocation
will be in the command output. Present it to the user clearly, noting:

- **Overall health** — ERRORS / WARNINGS / CLEAN
- **Top error containers** — ranked by count
- **Root cause notes** — which are startup noise vs real issues
- **Recommendation**

If the user wants to drill into a specific container log, use `read_file` directly:

```
watsonx-orchestrate-adk/server-logs/<SESSION>/<container>.log
```

No further scripts needed — Bob reads log files directly.

---

## Key options for wxo_bob_inspect.sh

| Option | Default | Purpose |
|---|---|---|
| `--capture` | off | Start `wxo_server_log_inspector.sh` in background before analysis |
| `--capture-seconds N` | 30 | How long to capture before stopping (only with `--capture`) |
| `--session YYYYMMDD_HHMMSS` | most-recent | Specific session to analyse |
| `--log-dir DIR` | `./server-logs` | Root directory of sessions |
| `--mode MODE` | `ask` | Bob chat mode (`ask`, `arch-review`, etc.) |
| `--question TEXT` | health prompt | Custom question for Bob |
| `--full-report` | off | Send entire `ANALYSIS_REPORT.md` to Bob (slower, ~291 KB) instead of the summary extract (~1.8 KB) |

## Why responses are fast

By default the script extracts only the **metadata table and Sessions Overview
table** (~44 lines, ~1.8 KB) and pipes that to Bob — not the full 1574-line report.
This reduces Bob's input by 163× and makes the response time seconds instead of
minutes.

Use `--full-report` when you need Bob to reason over the raw error log excerpts,
warning text, or per-container tails inside the full report.
