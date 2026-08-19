# Embedding agents in your application — the runtime REST API

This is the **server-to-server runtime API** for *consuming* an already-deployed
agent from your own application (web/mobile backend, service, IDE, another
agent). It is **not** the embedded web-chat widget — that is a *channel*
(`orchestrate channels`, UI-only, drop-in `<script>`). Use this API when you want
your application to own the UX and call the agent like any other backend service.

> The endpoint paths/shapes below are verified against the **local Developer
> Edition** (port `4321`) per IBM's runtime API reference. The same paths exist on
> SaaS/on-prem under the instance service URL — confirm against your environment
> and `wxo-docs` (`SearchIbmWatsonxOrchestrateAdk`) before shipping, since runtime
> APIs evolve faster than the ADK CLI.

---

## 1. Base URL & auth (the two things that differ per environment)

**Base URL** = `<service-url>/api/v1`
- **Local Developer Edition:** `http://localhost:4321/api/v1`
- **SaaS / on-prem:** the same **API service URL** you registered in §2a (the one
  containing `/instances/<id>`), with `/v1` appended — e.g.
  `https://api.<region>.watson-orchestrate.cloud.ibm.com/instances/<INSTANCE_ID>/v1`.
  **Live-verified (2.12.0, us-south):** the runtime paths are under `/v1/orchestrate/…`
  on SaaS — `GET <base>/v1/orchestrate/agents` → 200, `POST <base>/v1/orchestrate/runs`
  → 200; the bare `/v1/agents` and `/v1/runs` return **404** (`WXO-PROXY-14009E`). Do not
  drop the `/orchestrate` segment on SaaS.

**Auth** = `Authorization: Bearer <token>` on every request.
- **Local:** read the token the Developer Edition already minted:
  ```bash
  # auth.local.wxo_mcsp_token
  python3 -c "import yaml,os;print(yaml.safe_load(open(os.path.expanduser('~/.cache/orchestrate/credentials.yaml')))['auth']['local']['wxo_mcsp_token'])"
  ```
- **SaaS / on-prem:** exchange your IBM Cloud API key (or CPD creds) for a bearer
  token via the platform's IAM/MCSP token endpoint, then send it as the bearer.
  Tokens expire — refresh on `401`. (Same credential you pass to `env activate`.)

**`agent_id`** (needed by most endpoints): `orchestrate agents list -v` → copy the
agent's `id` (a UUID), **not** the display name and not the snake_case `name`.

> **Never ship the bearer token to a browser.** Put a thin proxy in your app
> backend that holds the token/API-key, forwards the user's message to wxO, and
> streams the reply back to the client. The token grants full tenant access.

---

## 2. Pick an endpoint family

| Endpoint | Shape | Use it when |
|----------|-------|-------------|
| `POST /orchestrate/{agent_id}/chat/completions` | **OpenAI-compatible** | Drop-in for anything that already speaks OpenAI Chat Completions (IDEs, LangChain, existing chat UIs). Simplest. |
| `POST /orchestrate/runs` (+ `GET /orchestrate/runs/{run_id}`) | **Rich, async** | You need tool-call/step outputs, fine-grained `llm_params` (e.g. greedy + `temperature: 0`), guardrails, or async polling. **Not** for token usage — see the warning in §4. |
| `POST /orchestrate/runs/stream` | Rich + SSE | Same richness, streamed token-by-token (identical to `runs?stream=true`). |
| `POST /completions`, `POST /completions/chat` | **Model only, no agent** | Call a raw LLM through the AI Gateway without any agent/tool routing. |

Rule of thumb: **`chat/completions` for portability, `orchestrate/runs` for fidelity.**

---

## 3. OpenAI-compatible: `/orchestrate/{agent_id}/chat/completions`

```bash
curl -sX POST "$BASE/orchestrate/$AGENT_ID/chat/completions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"stream": false, "messages": [{"role": "user", "content": "Hi"}]}'
```
Non-stream response — reply text is at **`choices[0].message.content`**; the
**`thread_id`** at the top level is what you reuse for multi-turn:
```json
{ "object": "chat.completion",
  "choices": [{ "message": {"role":"assistant","content":"Hello! ..."}, "finish_reason":"stop" }],
  "thread_id": "c61c0bf7-..." }
```
With `"stream": true` you get SSE `data:` lines of `object: "thread.message.delta"`,
each carrying a `choices[0].delta.content` chunk — concatenate the chunks.

---

## 4. Rich runs: `/orchestrate/runs` (+ poll) and `/orchestrate/runs/stream`

**Start a run** (note: `agent_id` is in the *body* here, not the path):
```bash
curl -sX POST "$BASE/orchestrate/runs" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"message": {"role":"user","content":"Hi"}, "agent_id": "'"$AGENT_ID"'"}'
# → { "thread_id": "...", "run_id": "...", "task_id": "...", "message_id": "..." }
```
This returns **immediately** with ids; poll for the result:
```bash
curl -sX GET "$BASE/orchestrate/runs/$RUN_ID" -H "Authorization: Bearer $TOKEN"
```
When `status: "completed"`, the reply text is at
**`result.data.message.content[0].text`**. `step_history` carries tool outputs.

The completed run also carries **`trace_id`** (32-hex) — capture it, it is your only handle
on the telemetry in [agentops-evaluations.md](agentops-evaluations.md) §4.

> ⚠ **`usage` is `null` — do NOT build token accounting on the runs API.** (live-verified
> 2.13.0 SaaS, every completed run). Both `usage` and `llm_params` are present-but-empty on
> the run object:
> ```json
> { "status": "completed", "trace_id": "291eb995…", "thread_id": "d2a6a5d6-…",
>   "usage": null, "llm_params": null }
> ```
> Exact per-call token counts **do** exist — in the trace, at
> `observation.usage.{input,output,total}` on `GENERATION` observations. Getting `null` here
> is the #1 reason people wrongly conclude wxO does not report tokens.
> Full field map: [agentops-evaluations.md](agentops-evaluations.md) §4.

`step_history` also has **no per-step timestamps**, so you cannot derive per-step latency
from it. That, too, lives in the trace (`observation.latency`).

**Streaming** (`/orchestrate/runs/stream`, or `/orchestrate/runs?stream=true`)
emits an SSE event sequence:
`run.started` → `message.started` → many `message.delta` (append
`data.delta.content[*].text`) → `message.created` (the final assembled message at
`data.message.content[0].text`) → `run.completed` → `done`.

To set decoding params, pass model settings (e.g. greedy / `temperature: 0`) in the
run body — confirm the exact field name (`llm_params`) for your version via
`wxo-docs`.

---

## 5. Multi-turn (conversation memory)

Both families return a **`thread_id`**. To continue the same conversation, send it
back on the next request:
- `chat/completions`: include the prior turns in `messages` **and** reuse the
  `thread_id`.
- `orchestrate/runs`: pass `"thread_id": "<id>"` in the body alongside `message`
  and `agent_id`.

This is the same `thread_id` continuity the multi-turn **verification gate** uses —
the Python SDK `RunClient` in [testing-debugging.md](testing-debugging.md) is just a
typed wrapper over these `/orchestrate/runs` endpoints. **Python apps → use
`RunClient`; non-Python apps → call the HTTP endpoints above directly.**

---

## 6. Model-only completions (no agent)

```bash
curl -sX POST "$BASE/completions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"model": "mistralai/mistral-large", "prompt": "Hi"}'

curl -sX POST "$BASE/completions/chat" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"model": "watsonx/meta-llama/llama-3-3-70b-instruct",
       "messages": [{"role":"user","content":"Hi"}], "stream": false}'
```
Use these to hit a Gateway model directly (no agent routing/tools). List available
model ids with `orchestrate models list` (see SKILL §4).

---

## 7. Minimal app-backend embedding pattern

```
browser ──user msg──▶ YOUR backend ──Bearer token──▶ wxO /orchestrate/runs(/stream)
        ◀─stream/text─┘  (holds token,            ◀── thread_id + reply
                          persists thread_id
                          per user session)
```
Checklist:
- **Token lives in the backend only** — never in client JS. Refresh on `401`.
- **Persist `thread_id` per user session** so each user keeps conversation memory.
- **Stream when the UX is a chat box** (`/stream` or `stream:true`); poll/await for
  fire-and-forget tasks.
- **Deploy first.** The agent must be imported and (on SaaS/on-prem) `deploy`-ed in
  the target env before the API will route to it; the `agent_id` is env-specific.
- **Choose by integration:** OpenAI-compatible clients → `chat/completions`; full
  control over tool steps and decoding → `orchestrate/runs`.

> When something here isn't spelled out (exact SaaS path, a body field, new
> events), query **`wxo-docs`** (`SearchIbmWatsonxOrchestrateAdk`) rather than
> guessing — runtime APIs change faster than this skill.

---

## 8. 2026 runtime/observability updates (verify per environment)

- **Standardized error responses** — all proxy errors now return a consistent JSON
  shape with **machine-readable error codes** and a **transaction ID**. Log the
  transaction ID and switch on the stable error code instead of parsing message
  strings; surface the id in your app's error reporting for support/troubleshooting.
- **Context compaction at the API level** — long-running conversations can overflow
  the context window. Enable compaction via the agent config (`compaction_settings`,
  see [agents-tools-schemas.md](agents-tools-schemas.md)) so multi-turn `thread_id`
  conversations summarize automatically (default threshold ~20,000 tokens) rather
  than failing.
- **AgentOps v3 traces** — retrieve execution traces via
  `GET v1/agentops-v3/traces/{trace_id}`. Context-variable changes are now tracked
  per node; client apps can also consume intermediate context updates through
  embedded-chat runtime events. Use this for production debugging of agentic
  workflows instead of the run `step_history` alone — it is also the **only** place
  token counts, per-span latency and the span tree exist. Field map and the
  native-vs-derive boundary: [agentops-evaluations.md](agentops-evaluations.md) §4–§6.
  ⚠ **Cost is not computed for you** — `totalCost` returns `0`; tokens are exact,
  pricing is yours (§5 there).
- **Sensitive-data masking** — values marked sensitive in a flow are masked in chat
  history, the flow inspector, and traces; don't expect to read them back from the
  trace/run output.
- **File upload (chat_with_docs / file-upload agents)** — `POST <base>/v1/orchestrate/upload-to-s3`
  (multipart: `files=<file>`, `data={text, fileMetaData}`) → returns COS presigned
  URLs. ⚠ The ADK `RunClient.upload_file_to_s3` posts to `/v1/upload-to-s3/` on cloud →
  **404**; use `/v1/orchestrate/upload-to-s3` (no trailing slash) → 200. **Note:** even
  with a valid upload, `chat_with_docs` agents did **not** read the file via
  `/v1/orchestrate/runs` in testing — that feature is wired for the chat-UI/web-chat
  upload widget. For programmatic document RAG, use a `knowledge_base` instead.
