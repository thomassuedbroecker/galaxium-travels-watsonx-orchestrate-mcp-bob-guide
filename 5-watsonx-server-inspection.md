# 5. Inspect The `watsonx Orchestrate` Server Logs

Use this guide to capture, analyse, and inspect the container logs produced by a
running `watsonx Orchestrate Developer Edition` server. Three automation scripts
in [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/) plus a Bob skill
drive the full pipeline:

| Artifact | Purpose |
|---|---|
| [`wxo_server_log_inspector.sh`](./watsonx-orchestrate-adk/wxo_server_log_inspector.sh) | Discovers all running containers and streams their logs in parallel to timestamped files |
| [`wxo_server_log_analyze.sh`](./watsonx-orchestrate-adk/wxo_server_log_analyze.sh) | Reads the captured files, produces a Sessions Overview, and writes `ANALYSIS_REPORT.md` |
| [`wxo_bob_inspect.sh`](./watsonx-orchestrate-adk/wxo_bob_inspect.sh) | Chains analysis + IBM Bob CLI in one command: pipes the report summary to `bob` for a structured verdict |
| [`.bob/skills/wxo-log-inspector/`](./.bob/skills/wxo-log-inspector/SKILL.md) | Bob skill — drives the full pipeline interactively from the terminal |

Run all commands from the **`watsonx-orchestrate-adk/`** directory unless a block
says otherwise. The Developer Edition must be running (see guide `3`) before you
start the inspector.

---

## 5.1 Prerequisites

| Requirement | Notes |
|---|---|
| Running Developer Edition | Start it with guide `3` (`wxo_local_start.sh`) |
| Python virtual environment | Created in guide `3` — activate with `source .venv/bin/activate` |
| `jq` | JSON processor used by the analyser — `brew install jq` (macOS) |
| `bob` CLI | IBM Bob CLI used in step 4 — `npm install -g @ibm/bob-cli` |

> **No system Docker required.**
> The Developer Edition runs inside a Lima VM managed by the ADK. The inspector
> uses the **bundled `limactl`** binary shipped inside the Python package to
> query containers directly — no host-level Docker Desktop installation is needed.

> **Why capture logs?**
> The Developer Edition runs as a set of Docker containers. Inspecting their
> logs during a test run lets you trace errors, session `thread_id` values,
> warnings, and model call patterns without needing to attach to each container
> individually. The captured `ANALYSIS_REPORT.md` is then fed directly to IBM
> Bob CLI for automated structured analysis — no watsonx Orchestrate agent needed.

---

## 5.2 Step 1 — Activate The Virtual Environment

Before running either script, activate the virtual environment so the
`orchestrate` command is available:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
```

---

## 5.3 Step 2 — Start The Log Inspector

> **This script runs continuously until you press `Ctrl-C`.**
> Open it in a **dedicated terminal** and leave it running while you use the
> server. When you are done with your session, switch back to this terminal
> and press `Ctrl-C` to stop the capture and see the summary.

### Capture all containers (default)

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_server_log_inspector.sh
# ↑ this runs until you press Ctrl-C in this terminal
```

The script does the following in order:

1. **Locates the bundled `limactl`** binary inside the Python package — no
   system-level Docker or limactl installation required.
2. **Discovers containers** by running `docker ps` inside the Lima VM via
   `limactl shell ibm-watsonx-orchestrate -- docker ps`.
3. **Creates the session directory** under `./server-logs/YYYYMMDD_HHMMSS/` and
   writes a `manifest.json` describing the session.
4. **Starts one `limactl shell … -- docker logs --follow` stream per container**
   in a background subshell, writing each to a dedicated `.log` file while
   printing every line to the terminal prefixed with `[container-name]`.
   > This bypasses the host Docker context entirely — the stream goes straight
   > through the Lima VM socket, which is the only socket that sees the
   > Developer Edition containers.
5. **Prints a heartbeat line every 5 seconds** showing the current line count
   per container — so you always see that capture is progressing.
6. **When you press `Ctrl-C`** — stops all background subshells, prints a
   per-container line-count summary, and prints the next command to run.

### What you will see in the terminal

After startup you will see the container list, then a continuous stream of log
lines followed by a heartbeat every 5 seconds:

```
========================================
 Activating virtual environment

========================================
 Locating bundled limactl
Found limactl: .../.venv/.../developer_edition/resources/lima/bin/limactl

========================================
 Discovering running watsonx Orchestrate containers
Found 25 container(s):
  • dev-edition-wxo-server-1
  • dev-edition-ui-1
  • dev-edition-wxo-server-worker-1
  • dev-edition-langfuse-web-1
  • dev-edition-langfuse-worker-1
  • dev-edition-ai-gateway-1
  • dev-edition-agent-runtime-1
  • dev-edition-tools-runtime-1
  • dev-edition-mcp-gateway-1
  • dev-edition-wxo-agent-gateway-1
  • dev-edition-wxo-builder-1
  • dev-edition-wxo-agentic-memory-1
  • dev-edition-wxo-tempus-runtime-1
  • dev-edition-wxo-knowledge-mcp-server-1
  • dev-edition-socket-handler-1
  • dev-edition-wxo-server-connection-manager-1
  • dev-edition-wxo-server-connections-ui-1
  • dev-edition-wxo-server-db-1
  • dev-edition-wxo-server-minio-1
  • dev-edition-wxo-server-redis-1
  • dev-edition-wxo-milvus-standalone-1
  • dev-edition-wxo-milvus-etcd-1
  • dev-edition-opensearch-1
  • clickhouse
  • dev-edition-tools-runtime-manager-1

========================================
 Streaming logs in parallel — press Ctrl-C to stop

[START] dev-edition-wxo-server-1 → ./server-logs/20250707_143022/dev-edition-wxo-server-1.log
[START] dev-edition-ui-1         → ./server-logs/20250707_143022/dev-edition-ui-1.log
...

All streams started. Log lines appear below prefixed with [container-name].
Press Ctrl-C to stop all streams and finalise the session.

[dev-edition-wxo-server-1] 2025-07-07 14:30:23 INFO  server ready on :4321
[dev-edition-ui-1]         2025-07-07 14:30:24 INFO  UI started on :3000
[5s]  dev-edition-wxo-server-1:12  dev-edition-ui-1:4  dev-edition-ai-gateway-1:5
[10s] dev-edition-wxo-server-1:24  dev-edition-ui-1:6  dev-edition-ai-gateway-1:9
...
```

> **The heartbeat line** (`[5s]`, `[10s]`, …) tells you the script is alive and
> shows how many lines have been written to each log file. If a container
> produces no logs the count stays at zero — that is normal for quiet services.

### Stop the inspector

The script does **not stop by itself** — it keeps streaming as long as the server
is running. When you have finished your tests or interactions, switch to this
terminal and press **`Ctrl-C`**. The script stops all streams and prints a summary:

```
Stopping all log streams...

========================================
 Session summary
  dev-edition-wxo-server-1:           312 lines → ./server-logs/20250707_143022/dev-edition-wxo-server-1.log
  dev-edition-ui-1:                    48 lines → ./server-logs/20250707_143022/dev-edition-ui-1.log
  dev-edition-langfuse-web-1:          21 lines → ./server-logs/20250707_143022/dev-edition-langfuse-web-1.log
  dev-edition-ai-gateway-1:           104 lines → ./server-logs/20250707_143022/dev-edition-ai-gateway-1.log
  ...
========================================
Session directory: ./server-logs/20250707_143022
Manifest:          ./server-logs/20250707_143022/manifest.json
To analyse:        bash wxo_server_log_analyze.sh
```

### Capture a single container by name

```sh
bash wxo_server_log_inspector.sh --name dev-edition-wxo-server-1
```

The named container must be currently running. If it is not, the script prints
the list of running containers and exits.

### Use a custom output directory

```sh
bash wxo_server_log_inspector.sh --log-dir /tmp/my-logs
```

### All options

```
Options:
  --env-file  -e   Path to a .env file (passed to orchestrate commands).
                   Defaults to .env if present.
  --log-dir   -d   Directory where captured log files are written.
                   Defaults to ./server-logs
  --name      -n   Capture a specific container by name instead of all.
  --help           Show this message and exit.
```

### Output layout

Each run creates a timestamped session directory:

```
watsonx-orchestrate-adk/
└── server-logs/
    └── 20250707_143022/
        ├── manifest.json                              ← session metadata
        ├── dev-edition-wxo-server-1.log
        ├── dev-edition-ui-1.log
        ├── dev-edition-langfuse-web-1.log
        ├── dev-edition-ai-gateway-1.log
        └── ...  (one .log per container)
```

> **Tip:** The session timestamp (`YYYYMMDD_HHMMSS`) is used by the analyser
> to locate the correct session. The most-recent session is selected automatically
> if you do not pass `--session`.

---

## 5.4 Step 3 — Analyse The Captured Logs

Run the analyser in any terminal after the inspector has stopped (or even
while it is still running — the files are valid at any point):

### Analyse the most recent session (default)

```sh
cd watsonx-orchestrate-adk
bash wxo_server_log_analyze.sh
```

### Analyse a specific session

```sh
bash wxo_server_log_analyze.sh --session 20250707_143022
```

### Change the number of tail lines shown per container

```sh
bash wxo_server_log_analyze.sh --tail 100
```

### Write the report to a custom path

```sh
bash wxo_server_log_analyze.sh --report /tmp/my-report.md
```

### All options

```
Options:
  --log-dir   -d   Root directory that contains timestamped session folders.
                   Defaults to ./server-logs
  --session   -s   Specific session timestamp folder to analyse.
                   Defaults to the most-recent session.
  --report    -r   Path for the Markdown report.
                   Defaults to <session-dir>/ANALYSIS_REPORT.md
  --tail      -t   Number of tail lines to include per container. Default 50.
  --help           Show this message and exit.
```

---

## 5.5 Sessions Overview — Reading The Output

The analyser prints a colour-coded summary table to the terminal:

```
Container                                   Lines   Errors Warnings   Sessions
---------------------------------------- -------- -------- -------- ----------
wxo-backend                                    42        2        3          7
wxo-ui                                          8        0        0          0
wxo-langfuse                                    6        0        1          2

TOTAL                                                    2        4
```

| Column | Meaning |
|---|---|
| **Lines** | Total lines in the captured log file |
| **Errors** | Lines matching `error`, `exception`, `fatal`, `panic`, or `critical` |
| **Warnings** | Lines matching `warn`, `warning`, or `deprecated` |
| **Sessions** | Lines containing `session` or `thread_id` |

Row colour:

| Colour | Meaning |
|---|---|
| Red | One or more errors detected |
| Yellow | Warnings only — no errors |
| Green | Clean — no errors or warnings |

After the table, each container's detail section shows:
- **Errors** — first 20 matching lines
- **Warnings** — first 10 matching lines
- **Top log-level tokens** — most frequent all-caps words (e.g. `ERROR`, `INFO`, `WARN`)
- **Tail** — the last N lines (default 50, controlled by `--tail`)

---

## 5.6 The Markdown Report

After the terminal output, the analyser writes `ANALYSIS_REPORT.md` into the
session directory:

```
server-logs/
└── 20250707_143022/
    ├── manifest.json
    ├── dev-edition-wxo-server-1.log
    ├── dev-edition-ui-1.log
    ├── dev-edition-langfuse-web-1.log
    ├── ...  (one .log per container)
    └── ANALYSIS_REPORT.md   ← generated by wxo_server_log_analyze.sh
```

The report contains:

- A summary metadata table (session, timestamp, total errors/warnings)
- The Sessions Overview table in Markdown
- Per-container sections with errors, warnings, session/`thread_id` references,
  top tokens, and a log tail

This file is the handover point for **Step 4** (section 5.9): `wxo_bob_inspect.sh`
extracts the summary section and pipes it to the IBM Bob CLI (`bob`) for a
structured health verdict — directly from the terminal, no agent deployment needed.

---

## 5.7 Exit Codes

The analyser exits with a code that reflects the overall log health — useful
when running it inside a CI pipeline or as part of a test suite:

| Exit code | Meaning |
|---|---|
| `0` | All logs clean — no errors or warnings |
| `1` | Warnings found, no errors |
| `2` | One or more errors found |

---

## 5.8 Running Both Scripts Together During A Test Run

The recommended workflow is two terminals side by side:

**Terminal 1 — capture logs throughout the test run:**

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_server_log_inspector.sh
# keep this running — press Ctrl-C when tests are done
```

**Terminal 2 — run your tests, then analyse:**

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate

# run your tests or agent interactions here ...

# when done, analyse the session
bash wxo_server_log_analyze.sh
```

---

## 5.9 Step 4 — Structured Analysis Via IBM Bob CLI

After capturing logs and generating `ANALYSIS_REPORT.md`, ask IBM Bob to inspect
and explain them. Bob reads the bash output and the report directly — no watsonx
Orchestrate agent deployment required.

### How it works

```
1. wxo_server_log_inspector.sh   captures logs → server-logs/<SESSION>/*.log
2. wxo_server_log_analyze.sh     reads logs    → server-logs/<SESSION>/ANALYSIS_REPORT.md
3. IBM Bob CLI reads the report and reasons over it
```

Bob handles step 3 through the `wxo-log-inspector` skill installed in `.bob/skills/`.
The skill tells Bob exactly how to run the bash scripts, read the generated report,
and present structured findings.

### Install the skill (once)

The skill is already in `.bob/skills/wxo-log-inspector/SKILL.md` in this repository.
It activates automatically in the next IBM Bob conversation — no install step needed
beyond having the file present.

### Use it

Open a new IBM Bob conversation and say any of:

```
inspect the watsonx Orchestrate server logs
```
```
check wxo server log health
```
```
analyse the most recent orchestrate log session
```

Bob will:

1. Check prerequisites (venv, active environment, `jq`)
2. List existing sessions or ask you to capture new ones
3. Run `wxo_server_log_analyze.sh` via `execute_command`
4. Read `ANALYSIS_REPORT.md` via `read_file`
5. Present a structured health report:

```
## wxO Server Log Health — Session 20260729_160447

Overall health: ERRORS

Sessions Overview
Container                                    Lines  Errors  Warnings  Session Refs
dev-edition-wxo-server-1                     6075   1714    1697      5688
dev-edition-wxo-server-worker-1             10429      5      15     10351
dev-edition-wxo-milvus-standalone-1          1391     75      98        60
...

Top containers by errors
1. dev-edition-wxo-server-1 — 1714 (mostly WARNING-level ValueError entries, not true errors)
2. dev-edition-wxo-milvus-standalone-1 — 75
3. dev-edition-mcp-gateway-1 — 17

Root cause notes
dev-edition-wxo-server-1: Secret-read warnings (PGBOUNCER_USER, INTERNAL_REQUEST_TOKEN)
are expected Developer Edition startup noise. The 5 true ERROR lines are Redis TRM cache
connection failures at boot — transient, self-resolving once Redis is ready.

Recommendation: server is functionally healthy. No actionable errors found.
```

### Capture fresh logs first (optional)

If you want Bob to inspect a brand-new run, start the inspector in a dedicated
terminal before starting the Bob conversation:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_server_log_inspector.sh
# run your tests or agent interactions, then press Ctrl-C
```

Then start the Bob conversation — it will find the new session automatically.

### `wxo_bob_inspect.sh` — the primary automated command

This is the **primary approach**: one command chains the full pipeline, invokes
`bob` directly from the terminal, and exports the result as a markdown file:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_bob_inspect.sh
```

The script runs the analyser, extracts the summary (≈44 lines), and pipes it to:

```sh
cat SUMMARY_BY_BOB.md \
  | bob --chat-mode ask --approval-mode yolo -p "<question>" \
  | tee -a BOB_ANALYSIS_REPORT.md
```

Bob's response is streamed to the terminal live and simultaneously written to
`<session-dir>/BOB_ANALYSIS_REPORT.md`. The file is prefixed with a metadata
header (session ID, Bob mode, context file, timestamp) so it stands alone as a
readable report.

Options:

```
--capture              Capture fresh logs first (background, stops automatically)
--capture-seconds N    How long to capture (default: 30s)
--question  -q         Custom question for Bob
--mode      -m         Bob chat mode: ask (default), arch-review, etc.
--export-file -o       Path for the exported Bob analysis markdown
                       (default: <session-dir>/BOB_ANALYSIS_REPORT.md)
--full-report          Send complete 1574-line report instead of 44-line summary
```

---

## 5.10 All Artifacts In This Guide

| Artifact | Location | Purpose |
|---|---|---|
| `wxo_server_log_inspector.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_server_log_inspector.sh) | Parallel log capture from all 25 containers via `limactl` |
| `wxo_server_log_analyze.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_server_log_analyze.sh) | Sessions Overview + `ANALYSIS_REPORT.md` + `SUMMARY_BY_BOB.md` |
| `wxo_bob_inspect.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_bob_inspect.sh) | **Primary**: chains analyse + pipes summary to `bob` CLI + exports `BOB_ANALYSIS_REPORT.md` |
| `BOB_ANALYSIS_REPORT.md` | `<session-dir>/` (generated) | Exported Bob analysis — metadata header + Bob's full response |
| `.bob/skills/wxo-log-inspector/SKILL.md` | [`.bob/skills/wxo-log-inspector/`](./.bob/skills/wxo-log-inspector/SKILL.md) | Bob skill — `wxo_bob_inspect.sh` reference + options |

---

### [Home](./README.md)
