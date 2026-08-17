# 6. Inspect The `watsonx Orchestrate` Server Logs

This guide shows how to capture, analyse, and interpret the container logs
produced by a running `watsonx Orchestrate Developer Edition` server, and then
ask IBM Bob to reason over the results.

| Script / Artifact | When to use |
|---|---|
| [`wxo_bob_log_inspect.sh`](./watsonx-orchestrate-adk/wxo_bob_log_inspect.sh) | **Primary command** — captures logs, analyses them, and asks Bob to explain the findings in one shot |
| [`wxo_server_log_inspector.sh`](./watsonx-orchestrate-adk/wxo_server_log_inspector.sh) | Continuous capture for an open-ended interactive session (dedicated terminal) |
| [`wxo_server_log_analyze.sh`](./watsonx-orchestrate-adk/wxo_server_log_analyze.sh) | Analyse already-captured log files independently |
| [`.bob/skills/wxo-log-inspector/`](./.bob/skills/wxo-log-inspector/SKILL.md) | IBM Bob skill — drives the full pipeline interactively from the Bob UI |

Run all commands from the **`watsonx-orchestrate-adk/`** directory unless a block
says otherwise.

---

## 6.1 What Is Server Log Inspection?

The `watsonx Orchestrate Developer Edition` runs as a set of Docker containers
inside a Lima VM managed by the ADK. Because the containers are isolated, there
is no direct way to see what is happening inside them without explicitly capturing
their output.

The log inspection pipeline solves this in three steps:

```
1. wxo_server_log_inspector.sh   streams container logs → server-logs/<SESSION>/*.log
2. wxo_server_log_analyze.sh     reads the files        → server-logs/<SESSION>/ANALYSIS_REPORT.md
3. IBM Bob CLI (bob run)         reasons over the report → server-logs/<SESSION>/BOB_ANALYSIS_REPORT.md
```

**Why inspect logs?**

- Trace errors, warnings, and `thread_id` values without attaching to each
  container individually.
- Determine whether error-count spikes are genuine failures or expected startup
  noise.
- Feed the captured report directly to IBM Bob for a structured health verdict —
  no watsonx Orchestrate agent deployment required.

> **No system Docker required.**
> The inspector uses the **bundled `limactl`** binary shipped inside the Python
> package to query containers directly. No host-level Docker Desktop installation
> is needed.

---

## 6.2 Prerequisites

| Requirement | How it is satisfied |
|---|---|
| Developer Edition running with the local environment active | `wxo_local_start.sh` (guide 3) |
| Python virtual environment | Created in guide 3 — activate with `source .venv/bin/activate` |
| `jq` | JSON processor used by the analyser — `brew install jq` (macOS) |
| IBM Bob CLI | `npm install -g @ibm/bob-cli` |
| `BOB_API_KEY` | Required for headless `bob run` — set in `.env` (see §6.3) |

> **If you already ran `wxo_local_start.sh` from guide 3, the Developer Edition
> and virtual environment are ready — skip the setup and go straight to §6.4.**

---

## 6.3 One-Time Setup

### Step 1 — Activate the virtual environment

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
```

### Step 2 — Copy the env template

```sh
cp watsonx-orchestrate-adk/.env_template watsonx-orchestrate-adk/.env
```

### Step 3 — Set BOB_API_KEY

`bob run` requires an API key for headless (non-interactive) use. Edit
`watsonx-orchestrate-adk/.env` and fill in:

```sh
export BOB_API_KEY=<YOUR_BOB_API_KEY>
```

Create the key at **bob.ibm.com → Account → API Keys** (scope: **Inference**).

### Step 4 — Verify the services

```sh
# Active orchestrate environment is 'local'
orchestrate env list
# expected: local (active)
```

If any check fails, re-run the start script:

```sh
bash wxo_local_start.sh
```

---

## 6.4 Log Capture Modes

> **Choose the right capture mode before running anything.**
>
> `wxo_server_log_inspector.sh` is a continuous `--follow` stream — it does **not**
> stop by itself. It must be stopped with `Ctrl-C` or killed externally.
> For exercises and scripted pipelines use `wxo_bob_log_inspect.sh --capture`
> instead — it wraps the inspector with an automatic timeout so you never need to
> manage a second terminal or press `Ctrl-C`.

| Mode | Command | Stops itself? | Use when |
|---|---|---|---|
| **Timed capture** ✅ recommended | `bash wxo_bob_log_inspect.sh --capture --capture-seconds 60` | Yes — after N seconds | Exercises, scripted pipelines, one-shot health checks |
| **Open-ended capture** | `bash wxo_server_log_inspector.sh` (dedicated terminal) | No — press `Ctrl-C` | You want logs from an entire interactive session of unknown length |

### Timed capture — stops automatically (recommended)

This single command captures logs for 60 seconds, stops the capture automatically,
runs the analyser, and passes the result directly to IBM Bob:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_bob_log_inspect.sh \
  --capture \
  --capture-seconds 60
```

Internally the script:
1. Starts `wxo_server_log_inspector.sh` as a background process
2. Waits exactly `--capture-seconds` seconds
3. Kills the background process — log files are now written to `./server-logs/YYYYMMDD_HHMMSS/`
4. Runs `wxo_server_log_analyze.sh` over the new session
5. Passes the summary to `bob run`

A new timestamped session directory is created every time — nothing from a
previous run is reused.

### What you will see in the terminal

```
════════════════════════════════════════
  Step 1 — Capturing logs for 60s
════════════════════════════════════════
Starting wxo_server_log_inspector.sh in background...
Capturing... (60s)
[dev-edition-wxo-server-1] {"time": "...", "level": "INFO", ...}
[dev-edition-ui-1]         {"time": "...", ...}
...
Stopping capture (PID 12345)...
Capture complete.

════════════════════════════════════════
  Step 2 — Resolving session
════════════════════════════════════════
Session:   20260816_162515
Directory: ./server-logs/20260816_162515

════════════════════════════════════════
  Step 3 — Pre-analysis (wxo_server_log_analyze.sh)
════════════════════════════════════════
...

════════════════════════════════════════
  Step 4 — IBM Bob CLI analysis (mode: ask)
════════════════════════════════════════
Building prompt → bob run --mode "ask" "<context+question>"
Output → terminal + ./server-logs/20260816_162515/BOB_ANALYSIS_REPORT.md

[Bob streams analysis here...]
```

### Open-ended capture — dedicated terminal (interactive sessions)

Use this mode when you want to capture logs across an entire interactive session
of unknown length — for example while you manually test an agent through the UI.

Open a **dedicated terminal** and leave it running while you work:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_server_log_inspector.sh
# ↑ keep this running — press Ctrl-C once when tests are done
```

The script discovers all containers, creates a session directory, and streams
logs until you press `Ctrl-C`. A single press stops all streams cleanly and
prints a per-container line-count summary:

```
Stopping all log streams...

========================================
 Session summary
  dev-edition-wxo-server-1:  312 lines → ./server-logs/20260816_162515/dev-edition-wxo-server-1.log
  dev-edition-ui-1:           48 lines → ./server-logs/20260816_162515/dev-edition-ui-1.log
  ...
========================================
Session directory: ./server-logs/20260816_162515
Manifest:          ./server-logs/20260816_162515/manifest.json
To analyse:        bash wxo_server_log_analyze.sh
```

When capture is done, run the analyser in a second terminal:

```sh
bash wxo_server_log_analyze.sh
```

### Capture a single container by name

```sh
bash wxo_server_log_inspector.sh --name dev-edition-wxo-server-1
```

### All options for `wxo_server_log_inspector.sh`

```
Options:
  --env-file  -e   Path to a .env file. Defaults to .env if present.
  --log-dir   -d   Directory where captured log files are written.
                   Defaults to ./server-logs
  --name      -n   Capture a specific container by name instead of all.
  --help           Show this message and exit.
```

### Output layout

Each run creates a new timestamped session directory:

```
watsonx-orchestrate-adk/
└── server-logs/
    └── 20260816_162515/
        ├── manifest.json                              ← session metadata
        ├── dev-edition-wxo-server-1.log
        ├── dev-edition-ui-1.log
        ├── dev-edition-langfuse-web-1.log
        ├── dev-edition-ai-gateway-1.log
        └── ...  (one .log per container)
```

---

## 6.5 Analyse The Captured Logs

Run the analyser after capture has stopped (or while it is still running — the
log files are valid at any point):

### Analyse the most recent session (default)

```sh
cd watsonx-orchestrate-adk
bash wxo_server_log_analyze.sh
```

### Analyse a specific session

```sh
bash wxo_server_log_analyze.sh --session 20260816_162515
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

## 6.6 Sessions Overview — Reading The Output

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

> **The "Errors" count is broad by design.** It counts all lines matching
> error-related patterns — including lines with uppercase `ERROR` tokens inside
> INFO-level messages, stack-trace lines, and WARNING entries formatted as errors.
> A large Errors count in the Sessions Overview does not necessarily mean the
> server is broken. Always verify with `grep '"level": "ERROR"'` against the
> specific log file to count true `ERROR`-level JSON entries. See §6.8 for the
> worked example.

---

## 6.7 The Markdown Report

After the terminal output, the analyser writes `ANALYSIS_REPORT.md` into the
session directory:

```
server-logs/
└── 20260816_162515/
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

This file is the handover point for **§6.9** (Structured Analysis Via IBM Bob CLI): `wxo_bob_log_inspect.sh`
extracts the summary section and passes it to `bob run` for a structured health
verdict — directly from the terminal, no agent deployment needed.

---

## 6.8 Exit Codes

The analyser exits with a code that reflects the overall log health — useful
when running it inside a CI pipeline or as part of a test suite:

| Exit code | Meaning |
|---|---|
| `0` | All logs clean — no errors or warnings |
| `1` | Warnings found, no errors |
| `2` | One or more errors found |

---

## 6.9 Worked Example — How Many Real Errors Are in `dev-edition-wxo-server-1.log`?

### 6.9.1 Scenario Definition

Before running any command, define what you are trying to find out and what a
healthy result looks like. This makes the Bob question precise and the result
verifiable.

| Field | Value |
|---|---|
| **Container under test** | `dev-edition-wxo-server-1` — the core backend |
| **Capture window** | 60 seconds of fresh logs while the server is idle |
| **Objective** | Determine how many true `ERROR`-level log entries exist and whether they are actionable |
| **Success criteria** | Bob identifies ≤ 2 distinct error messages; both are classified as startup noise; no actionable errors remain |
| **Anomaly watch list** | Any error message not listed in §6.9 Step 6; any error flagged as actionable; error count > 10 |
| **Script** | `wxo_bob_log_inspect.sh` — captures, analyses, and asks Bob in one command |
| **Bob question focus** | *"How many lines have level ERROR? List each distinct error message and state whether it is actionable or startup noise."* |

### 6.9.2 Worked Exercise — Are The Server Errors Actionable?

#### Step 1 — Confirm prerequisites

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate

# Developer Edition must be running
orchestrate env list
# Expected: local  (active)

# BOB_API_KEY must be set
grep BOB_API_KEY .env
# Expected: export BOB_API_KEY=<your-key>
```

If any check fails, re-run the start script:

```sh
bash wxo_local_start.sh
```

#### Step 2 — Run the full pipeline with timed capture

This single command captures fresh logs for 60 seconds, stops the capture
automatically, runs the analyser, and passes the result to IBM Bob with a
focused question about `dev-edition-wxo-server-1`:

```sh
bash wxo_bob_log_inspect.sh \
  --capture \
  --capture-seconds 60 \
  -q "Focus on dev-edition-wxo-server-1 only. How many lines have level ERROR? \
List each distinct error message and state whether it is actionable or startup noise."
```

> **What happens step by step:**
> 1. `wxo_server_log_inspector.sh` starts in the background and begins streaming
>    all container logs to a new `./server-logs/YYYYMMDD_HHMMSS/` directory.
> 2. After 60 seconds the background process is killed automatically — fresh log
>    files are now on disk.
> 3. `wxo_server_log_analyze.sh` reads the new session and writes `ANALYSIS_REPORT.md`.
> 4. The 44-line summary (metadata table + Sessions Overview) is extracted and
>    passed to `bob run --mode ask` together with your question.
> 5. Bob's response streams to the terminal and is written to `BOB_ANALYSIS_REPORT.md`.

You will see the capture phase, then the analysis phase, then Bob's live response —
all in one terminal, no `Ctrl-C` required.

#### Step 3 — Interact with the agent during capture (optional but recommended)

While the 60-second capture window is running, open a browser and send a message
to the watsonx Orchestrate chat UI:

```
http://localhost:3000/chat
```

Type a short greeting — for example `"Hello, are you working?"` — and submit it.
The agent interaction triggers a live LLM call that flows through the backend
containers. Its log lines (session `thread_id`, model call, response marshalling)
will appear in the captured files alongside any startup entries.

> **Why do this?**
> An idle server produces only startup noise in its logs. Sending one real message
> during capture lets you see what a genuine agent call looks like in the Sessions
> Overview — and whether it introduces any new errors or warnings beyond the two
> expected startup entries. It also gives Bob more signal to reason over, making
> the analysis more representative of a real workload.

> **What to look for afterwards:**
> The Sessions Overview "Sessions" column for `dev-edition-wxo-server-1` should
> increment (each agent run records a `thread_id`). If the value stays at `0` after
> your chat interaction, the request did not reach the backend — check that
> `orchestrate env list` still shows `local (active)`.

#### Step 4 — Follow the terminal output

```
════════════════════════════════════════
  Step 1 — Capturing logs for 60s
════════════════════════════════════════
Starting wxo_server_log_inspector.sh in background...
Capturing... (60s)
...
Stopping capture (PID 12345)...
Capture complete.

════════════════════════════════════════
  Step 2 — Resolving session
════════════════════════════════════════
Session:   20260816_162515
Directory: ./server-logs/20260816_162515

════════════════════════════════════════
  Step 3 — Pre-analysis (wxo_server_log_analyze.sh)
════════════════════════════════════════
...

════════════════════════════════════════
  Step 4 — IBM Bob CLI analysis (mode: ask)
════════════════════════════════════════
[Bob streams analysis here...]

════════════════════════════════════════
Report: ./server-logs/20260816_162515/BOB_ANALYSIS_REPORT.md
```

#### Step 5 — Read the exported report

```sh
cat server-logs/$(ls server-logs/ | sort | tail -1)/BOB_ANALYSIS_REPORT.md
```

The Sessions Overview in the report will show `dev-edition-wxo-server-1` as the
dominant container — likely with a large "Errors" count (hundreds). Bob's answer
to your question will explain what that count actually means.

#### Step 6 — Verify the raw ERROR count yourself

Bob's analysis identifies the true `ERROR`-level entries. Confirm with `grep`:

```sh
grep '"level": "ERROR"' \
  server-logs/$(ls server-logs/ | sort | tail -1)/dev-edition-wxo-server-1.log
```

During a normal Developer Edition startup you will see exactly two distinct error
messages, both repeated once per worker process:

| Error message | Source | Actionable? |
|---|---|---|
| `Failed to connect to Redis for TRM cache: Error 111 connecting to localhost:6379. Connection refused.` | `trm_response_cache.py` | ❌ No — Redis starts after the server workers; connection retries automatically |
| `Could not create /gitops: [Errno 13] Permission denied: '/gitops'` | `gitops.py` | ❌ No — GitOps directory creation is skipped in the Developer Edition; expected |

#### Step 7 — Verify against the scenario definition

Check every item from the scenario (§6.9.1) against what Bob reports:

| Scenario check | Where to look in the report | Pass condition |
|---|---|---|
| ERROR count | Bob's direct answer to the question | ≤ 2 distinct messages |
| Both errors are startup noise | Bob's classification per error | Both marked ❌ not actionable |
| No new/unexpected errors | Bob's anomaly section | No additional errors listed |
| Sessions Overview count vs. true ERROR count | Bob's explanation | Large count explained as broad pattern matching |

> **The large "Errors" count is expected and not a failure.** The Sessions Overview
> counts all lines that match a broad error-pattern regex — including INFO messages
> that contain the word "error". The `grep '"level": "ERROR"'` count is the
> definitive source of truth. Bob's analysis will explain the difference.

#### Step 8 — Understand the count difference

Bob's report will show a large "Errors" count (e.g. 891) in the Sessions Overview
next to `dev-edition-wxo-server-1`. The `grep` above returns only ~10 lines.
The difference is:

| Count source | What it counts |
|---|---|
| Sessions Overview "Errors" | Lines matching a **broad error-pattern regex** — includes WARNING-formatted lines, stack traces, lines containing the word "error" inside an INFO message |
| `grep '"level": "ERROR"'` | Lines where the JSON field `"level"` is **exactly** `"ERROR"` |

The Sessions Overview count is intentionally broad — it is designed to surface all
anomalies, not only `ERROR`-level JSON. Always run `grep '"level": "ERROR"'` when
the Sessions Overview number looks alarming.

---

## 6.10 Structured Analysis Via IBM Bob CLI

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
5. Present a structured health report

### `wxo_bob_log_inspect.sh` — the primary automated command

This is the **primary approach**: one command chains the full pipeline, invokes
`bob` directly from the terminal, and exports the result as a markdown file:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_bob_log_inspect.sh
```

The script runs the analyser, extracts the summary (≈44 lines), and passes it to:

```sh
bob run --mode ask "${SUMMARY_CONTENT}

${QUESTION}" | tee -a BOB_ANALYSIS_REPORT.md
```

Bob's response is streamed to the terminal live and simultaneously written to
`<session-dir>/BOB_ANALYSIS_REPORT.md`.

The exported file is clean, valid Markdown. A post-processing step runs automatically
after `bob run` completes and converts the raw terminal output into proper GFM:

| Transform | What it does |
|---|---|
| Bob conversation frame | Strips `User (N) …` / `Assistant (N) …` timestamp lines and `────…` separator lines |
| Terminal padding | Removes trailing whitespace from every line |
| Box-drawing tables | Converts Unicode `┌─┬─┐ │ ├─┼─┤ └─┴─┘` tables to GFM `\| col \| col \|` pipe tables |
| Single-column blocks | Converts `│ prose │` blocks to `> blockquote` |
| Horizontal rules | Converts `────…` lines to `---` |
| Bare section titles | Promotes standalone short lines to `### heading` |
| Echoed prompt | Strips the prompt echo that Bob prefixes before its answer |

The file is prefixed with a metadata header (session ID, Bob mode, context file,
timestamp) and ends with an **IBM Bob CLI Usage** section (wall-clock time, prompt
size, cost note).

### All options for `wxo_bob_log_inspect.sh`

```
Options:
  --capture              Capture fresh logs first (background, stops automatically)
  --capture-seconds N    How long to capture in seconds (default: 30)
  --session   -s         Specific session timestamp (YYYYMMDD_HHMMSS) to analyse
                         Defaults to the most-recent session
  --log-dir   -d         Root directory of session folders. Default: ./server-logs
  --question  -q         Custom question for Bob
  --mode      -m         Bob run mode: ask (default), arch-review, etc.
  --export-file -o       Path for the exported Bob analysis markdown
                         Default: <session-dir>/BOB_ANALYSIS_REPORT.md
  --env-file  -e         Path to a .env file. Default: .env
  --full-report          Send the complete ANALYSIS_REPORT.md to Bob instead of
                         the 44-line summary. Slower but gives Bob full log detail.
  --help                 Show this message and exit.
```

### Usage examples

Each example states its **objective** — what you are trying to find out — so you
can pick the right combination of flags for your situation.

```sh
# Objective: general health check — capture 60 s of fresh logs and ask Bob
# for a structured overview of errors, warnings, and session counts.
bash wxo_bob_log_inspect.sh --capture --capture-seconds 60

# Objective: investigate a specific container — focus Bob's analysis on
# the main backend and ask it to classify every ERROR-level entry.
bash wxo_bob_log_inspect.sh \
  --capture --capture-seconds 60 \
  -q "Focus on dev-edition-wxo-server-1. How many ERROR-level lines are there \
and are they actionable?"

# Objective: deeper architectural analysis — use arch-review mode to
# evaluate whether the log patterns indicate a structural problem.
bash wxo_bob_log_inspect.sh --capture --capture-seconds 60 --mode arch-review

# Objective: send the complete report to Bob (all containers, all log tails)
# when the 44-line summary is not enough detail.
bash wxo_bob_log_inspect.sh --capture --capture-seconds 60 --full-report

# Objective: save Bob's response to a dated archive path for a nightly
# CI job or scheduled health check.
bash wxo_bob_log_inspect.sh --capture --capture-seconds 60 \
  -o ./reports/health_$(date +%Y%m%d).md
```

---

## 6.11 Running Both Scripts Together During An Interactive Session

For an interactive test session where you control the start and end manually,
use two terminals side by side:

**Terminal 1 — capture logs throughout the session:**

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
bash wxo_server_log_inspector.sh
# keep this running — press Ctrl-C once when your session is done
```

**Terminal 2 — run your tests, then analyse:**

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate

# run your tests or agent interactions here ...

# when done, analyse the session and ask Bob
bash wxo_bob_log_inspect.sh
```

---

## 6.12 Known Issues

### `Ctrl-C` restarts the inspector instead of stopping it

**Status:** Fixed in this repository (commit: `wxo_server_log_inspector.sh` — fix Ctrl-C trap re-entry and heartbeat loop).

**Symptom:** Pressing `Ctrl-C` while `wxo_server_log_inspector.sh` is running causes
the script to briefly print "Stopping all log streams..." and then immediately resume
outputting log lines as if nothing happened. A second or third `Ctrl-C` has the same
effect.

**Root cause — two bugs in the original script:**

1. **`trap` registered before function defined** (minor, benign in most shells):
   `trap '_inspector_stop' INT TERM` was placed before `_inspector_stop()` was declared.

2. **`sleep 5` in the heartbeat loop intercepted `SIGINT` before the trap:**
   ```bash
   while true; do
     sleep 5        # ← Ctrl-C kills this sleep, loop restarts immediately
     ...
   done
   ```
   When `Ctrl-C` is pressed, `SIGINT` is delivered to the entire foreground process
   group. The `sleep 5` subprocess receives it, exits, and the `while true` loop
   restarts the next `sleep 5` before the trap handler can run its `exit 0`. A second
   `Ctrl-C` during the `wait "${PIDS[@]}"` call in `_inspector_stop` aborted cleanup
   before `exit 0` was reached — leaving the loop running.

**Fix applied:**

```bash
# 1. Function defined BEFORE trap registration
_inspector_stop() {
  trap '' INT TERM   # block re-entry — second Ctrl-C during cleanup is ignored
  echo "Stopping..."
  kill "${PIDS[@]}" 2>/dev/null
  wait "${PIDS[@]}" 2>/dev/null
  # ... summary ...
  exit 0
}
trap '_inspector_stop' INT TERM

# 2. sleep as a background job — wait is interruptible, loop is not
while true; do
  sleep 5 &
  SLEEP_PID=$!
  wait ${SLEEP_PID}
  [ $? -ne 0 ] && break   # Ctrl-C makes wait return non-zero → clean exit
  ...
done
```

With the fix, a single `Ctrl-C` stops all streams, prints the summary, and exits.

**Workaround (if running an older version):** Use `wxo_bob_log_inspect.sh --capture`
instead of running `wxo_server_log_inspector.sh` directly. The `--capture` path kills
the inspector via `kill $INSPECTOR_PID` from the parent shell, bypassing the broken
trap entirely.

---

## 6.13 All Artifacts In This Guide

| Artifact | Location | Purpose |
|---|---|---|
| `wxo_server_log_inspector.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_server_log_inspector.sh) | Parallel log capture from all containers via `limactl` |
| `wxo_server_log_analyze.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_server_log_analyze.sh) | Sessions Overview + `ANALYSIS_REPORT.md` + `SUMMARY_BY_BOB.md` |
| `wxo_bob_log_inspect.sh` | [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/wxo_bob_log_inspect.sh) | **Primary**: chains capture + analyse + `bob run` + exports clean GFM `BOB_ANALYSIS_REPORT.md` |
| `BOB_ANALYSIS_REPORT.md` | `<session-dir>/` (generated) | Clean GFM report — metadata header + Bob's analysis + IBM Bob CLI Usage section |
| `.bob/skills/wxo-log-inspector/SKILL.md` | [`.bob/skills/wxo-log-inspector/`](./.bob/skills/wxo-log-inspector/SKILL.md) | Bob skill — `wxo_bob_log_inspect.sh` reference + options |

---

### [Home](./README.md)
