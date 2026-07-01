# AgentOps — evaluating & observing wxO agents

The **AgentOps** layer is how you measure agent quality (evaluations) and inspect agent
behavior (observability/traces). It complements the §3.6 single/multi-turn smoke gate
with repeatable, metric-driven testing — use it before promoting an agent or after any
change that could regress behavior.

> **Install requirement (verified 2.12.0):** the evaluation *engine* ships as an extra,
> not in the base install. The `orchestrate evaluations …` CLI commands exist either way,
> but without the extra they fail at runtime with `ModuleNotFoundError: No module named
> 'agentops'`. Install it first:
> ```bash
> pip install "ibm-watsonx-orchestrate[agentops]"        # or:
> uv pip install --python .venv/bin/python "ibm-watsonx-orchestrate[agentops]"
> ```
> Evaluations also need watsonx.ai credentials in your `.env` (the framework calls an
> LLM as judge / to synthesize tests) — `validate-native` runs `validate_watsonx_credentials`.

---

## 1. The evaluations CLI (verified flags, 2.12.0)

`orchestrate evaluations <cmd>` — runs against the **active env**:

| Command | What it does | Key flags |
|---------|--------------|-----------|
| `generate` | Synthesize test cases from user stories | `--stories-path/-s` (CSV, **required**), `--tools-path/-t` (**required**), `--output-dir/-o`, `--env-file/-e` |
| `quick-eval` | Score an agent on static + LLM-as-judge metrics | `--config/-c` (YAML), `--test-paths/-p` (comma-sep), `--tools-path/-t`, `--output-dir/-o`, `--env-file/-e` |
| `evaluate` | Full eval against a set of test cases | `--config/-c` (YAML), `--test-paths/-p`, `--output-dir/-o`, `--env-file/-e` |
| `analyze` | Analyze a finished eval run | `--data-path/-d` (**required**), `--tools-path/-t`, `--mode/-m` `default\|enhanced` |
| `record` | Record chat sessions → test cases | (interactive) |
| `validate-native` | Validate a native agent against inputs | `--tsv/-t` (**required**), `--output/-o` (default `./test_native_agent`), `--env-file/-e` |
| `validate-external` | Validate an external agent | `--tsv/-t`, `--output/-o`, … |
| `red-teaming` | Generate + run adversarial attacks | see `--help` |

Always confirm with `orchestrate evaluations <cmd> --help` for your version.

## 2. Input formats (verified from source)

**`validate-native` / `validate-external` — TSV** (tab-separated, one test per line):
```
<user story / goal>	<expected final outcome>	<agent_name>
```
- Column 1 = the user's goal/story, column 2 = expected outcome, column 3 = the
  **snake_case agent `name`** (not display name). `validate-native` synthesizes a
  performance test from each row, then runs the evaluation.

**`generate` — stories CSV** with **`story` and `agent` columns**:
```csv
story,agent
"Ask for a differential for fever and a rash",dr_house_advise
"Ask who Wilson is",dr_house_advise
```
Plus `--tools-path` pointing at the directory holding the tool source `.py` files.

**`quick-eval` / `evaluate` — a YAML `--config`** + `--test-paths` (test-case JSON files
or dirs) + `--tools-path`. Generate the test cases first with `generate`, or hand-author
them, then point `--test-paths` at the output directory.

## 3. Typical workflow

```bash
# 0) one-time: install the engine
pip install "ibm-watsonx-orchestrate[agentops]"

# 1) generate test cases from user stories
orchestrate evaluations generate -s stories.csv -t ./tools -o ./eval/generated

# 2) run the evaluation (static + LLM-judge metrics)
orchestrate evaluations evaluate -p ./eval/generated -t ./tools -o ./eval/results
#    or a fast pass:
orchestrate evaluations quick-eval -p ./eval/generated -t ./tools -o ./eval/results

# 3) analyze (enhanced adds tool-level enrichment)
orchestrate evaluations analyze -d ./eval/results -t ./tools -m enhanced

# Fast path for a native agent without authoring JSON test cases:
orchestrate evaluations validate-native --tsv native_tests.tsv -o ./eval/out
```
Results (metrics, per-test pass/fail, judge rationales) are written under `--output-dir`.

## 4. Observability / traces (the "Ops" half)

Evaluations tell you *how well*; traces tell you *why*. Every `/v1/orchestrate/runs`
response carries a `trace_id` — capture it and pull the trace:

```bash
orchestrate observability traces export --trace-id <trace_id>        # full spans
# Rich JSON (observations, latency, scores, cost) via AgentOps v3:
curl -H "Authorization: Bearer $TOKEN" "<instance-url>/v1/agentops-v3/traces/<trace_id>"
```
On IBM Cloud SaaS, prefer `traces export --trace-id` over `traces search` (the latter
returned 0 results in testing even when traces existed — see
[testing-debugging.md](testing-debugging.md) §4). Context-variable changes are tracked
per node in 2.12; sensitive (masked) flow values are redacted in traces.

## 5. When to reach for what

- **Quick confidence after a change** → §3.6 single + multi-turn smoke gate (no extra needed).
- **Repeatable quality bar / regression suite** → `generate` + `evaluate`/`quick-eval`.
- **Adversarial / safety** → `red-teaming`.
- **Root-cause a bad answer** → `traces export --trace-id` / AgentOps v3 API.

> Runnable patterns: the public `examples/evaluations/` directory
> (https://github.com/IBM/ibm-watsonx-orchestrate-adk/tree/main/examples/evaluations) —
> evaluate, generate, analysis, red-teaming, rubric_evals, quick-eval, with-context-variable.
