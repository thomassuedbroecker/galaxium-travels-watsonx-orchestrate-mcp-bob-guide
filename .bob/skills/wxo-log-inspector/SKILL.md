---
name: wxo-log-inspector
description: >
  Use when the user wants to inspect, analyze, or review watsonx Orchestrate
  Developer Edition server logs with IBM Bob. Trigger phrases: "inspect server
  logs", "analyze wxo logs", "check container errors", "log inspector",
  "wxo_bob_log_inspect", "wxo_server_log_inspector", "wxo_server_log_analyze",
  "server log health check".
metadata:
  disable-model-invocation: false
---

# wxo-log-inspector

Capture watsonx Orchestrate server container logs, pre-analyze them, and ask
IBM Bob for a health report. All scripts live in `watsonx-orchestrate-adk/`.

| Script | Purpose |
|---|---|
| `wxo_server_log_inspector.sh` | Capture logs of all running containers into `server-logs/<YYYYMMDD_HHMMSS>/` |
| `wxo_server_log_analyze.sh` | Pre-analysis, writes `ANALYSIS_REPORT.md` |
| `wxo_bob_log_inspect.sh` | Pipeline: (capture) → analyze → `bob run` → Bob report |

---

## Step 1 — Verify prerequisites

```bash
which bob && bob --version 2>&1 | head -3
which jq
orchestrate env list 2>/dev/null | grep active
```

- `bob` and `jq` must be on PATH.
- The server must be running (`bash wxo_local_start.sh`) when using `--capture`.
- `BOB_API_KEY` must be set in `watsonx-orchestrate-adk/.env` (guide §6.3).

---

## Step 2 — Run the pipeline

Run from `watsonx-orchestrate-adk/`, ideally in a **new terminal**:

```bash
cd watsonx-orchestrate-adk && source .venv/bin/activate && \
  bash wxo_bob_log_inspect.sh --capture --capture-seconds 30
```

**Common variants:**

```bash
# Analyze the most recent existing session (no capture)
bash wxo_bob_log_inspect.sh

# Specific session
bash wxo_bob_log_inspect.sh -s 20260101_120000

# Send the complete report to Bob instead of the summary extract
bash wxo_bob_log_inspect.sh --full-report

# Custom question / Bob mode / output file
bash wxo_bob_log_inspect.sh -q "Which containers had Redis connection errors?"
bash wxo_bob_log_inspect.sh --mode arch-review
bash wxo_bob_log_inspect.sh -o ./my-report.md
```

**Output (in `server-logs/<session>/`):**

| File | Content |
|---|---|
| `<container>.log`, `manifest.json` | Raw logs (when captured) |
| `ANALYSIS_REPORT.md` | Full pre-analysis |
| `SUMMARY_BY_BOB.md` | Summary extract sent to Bob (default) |
| `BOB_ANALYSIS_REPORT.md` | Bob's cleaned answer (default `--export-file`) |

---

## Step 3 — Present the analysis

Read the Bob report with `read_file` and summarize: overall health, Sessions
Overview, top containers by error count, and which errors are Developer Edition
startup noise versus real issues. See guide §6 for details.

If a report is missing, check that a session folder exists in `server-logs/`;
otherwise re-run with `--capture`.
