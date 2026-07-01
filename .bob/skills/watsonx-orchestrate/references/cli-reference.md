# `orchestrate` CLI reference

Verified against **`ibm-watsonx-orchestrate` 2.12.0** (groups/commands confirmed live;
original catalog from 2.10.0). The CLI evolves — **always confirm with
`orchestrate <group> --help` and `orchestrate <group> <cmd> --help`**. Short flags are
shown in `()`.

Top-level groups:
`env`, `agents`, `tools`, `toolkits`, `knowledge-bases`, `connections`,
`models`, `server`, `chat`, `channels`, `settings`, `evaluations`,
`observability`, `voice-configs`, `phone`, `partners`, `workspaces`.

> Note the plural **`toolkits`** and **`voice-configs`** group names.

> **2.11–2.12 additions (from release notes, not yet live-verified — confirm with
> `--help`):**
> - **Scheduling:** agents/flows support recurring runs via `is_schedulable` in YAML
>   (internal scheduling tools then auto-appear); schedules themselves are created
>   conversationally in chat, not via a dedicated CLI verb.
> - **Custom / LangGraph agents (GA):** create and import custom agents from files
>   via `agents create` / `agents import`, including **mapping connections during
>   import from a ZIP** (look for a config/experimental-config flag on `agents
>   import --help`). LangGraph agents gained checkpointing + context variables.
> - **Compaction & per-agent decoding:** new `compaction_settings` / `llm_config`
>   YAML blocks (see agents-tools-schemas.md) — set in YAML, imported as usual.
> - **MCP toolkit export** and **dynamic KB schemas** were added around 2.10.
> - **Voice:** Deepgram **Flux** models (Flux General English is the new default,
>   Flux Multilingual, Nova-3 Medical) selectable in `voice-configs`.

---

## env — environments

| Command | Key options |
|---------|-------------|
| `env list` | — |
| `env add` | `--name(-n)`, `--url(-u)`, `--type(-t)`, `--iam-url(-i)`, `--activate(-a)`, `--insecure`, `--verify` |
| `env activate <name>` | *(name is positional)* `--api-key(-a)` (WXO/CPD; blank for local), `--username(-u)` (CPD), `--password(-p)` (CPD), `--skip-version-check`/`--enable-version-check` |
| `env remove` | `--name(-n)` |

```bash
orchestrate env list
orchestrate env activate local
orchestrate env add -n prod -u https://api.us-south.watson-orchestrate.cloud.ibm.com/instances/XXXX
orchestrate env activate prod --api-key "$IBM_CLOUD_API_KEY"
orchestrate env remove --name prod
```

Local CLI config lives at `~/.config/orchestrate/config.yaml` (shows
`context.active_environment` and per-env `wxo_url`/`auth_type`).

---

## agents

| Command | Key options |
|---------|-------------|
| `agents import` | `--file(-f)`, `--app-id(-a)` (external agents), `--safe` |
| `agents create` | `--name(-n)`, `--kind(-k)`, `--description`, `--llm`, `--style`, `--instructions`, `--tools`, `--collaborators`, `--knowledge-bases`, `--output(-o)`, external: `--title(-t)`, `--api(-a)`, `--auth-scheme`, `--provider(-p)`, `--auth-config`, `--nickname`, `--app-id`, `--context-access-enabled`, `--context-variable(-v)` |
| `agents list` | `--kind(-k)`, `--verbose(-v)` |
| `agents export` | `--name(-n)`, `--kind(-k)`, `--output(-o)`, `--agent-only` |
| `agents deploy` | `--name(-n)` |
| `agents undeploy` | `--name(-n)` |
| `agents remove` | `--name(-n)`, `--kind(-k)` |
| `agents copy` | `--name(-n)`, `--destination(-d)`, `--source(-s)` |
| `agents discover` | A2A discovery: `--url(-u)`, `--endpoint(-e)` (default `.well-known/agent-card.json`), `--name(-n)`, `--app-id(-a)` |
| `agents ai-builder` | AI-assisted agent builder |

```bash
orchestrate agents import -f agents/weather_agent.yaml
orchestrate agents list -k native -v
orchestrate agents export -n weather_agent -k native -o weather_agent.yaml --agent-only
orchestrate agents deploy -n weather_agent
```

`--kind` is `native | external | assistant`.

---

## tools

| Command | Key options |
|---------|-------------|
| `tools import` | `--kind(-k) python\|openapi\|flow\|langflow`, `--file(-f)`, `--requirements-file(-r)`, `--package-root(-p)`, `--app-id(-a)` (repeatable), `--name(-n)`, `--auto-discover`, `--llm`, `--env-file`, `--function`, `--save-flow-json`, `--safe` |
| `tools list` | `--verbose(-v)` |
| `tools export` | `--name(-n)`, `--output(-o)` |
| `tools remove` | `--name(-n)` |

```bash
orchestrate tools import -k python -f tools/weather.py -r tools/requirements.txt
orchestrate tools import -k python -f tools/api_tool.py --app-id my_api
orchestrate tools import -k openapi -f specs/petstore.yaml
orchestrate tools import -k flow -f tools/my_flow.py
```

- `--package-root(-p)` when a python tool spans multiple files in a package dir.
- `--auto-discover` (python only) generates docstrings/tools via an LLM (`--llm`, `--env-file`, `--function`).

---

## toolkits — MCP toolkits

Group is **`toolkits`** (plural) in 2.10.0. Two ways in: `add` configures inline;
`import` reads a pre-written MCP spec file.

| Command | Key options |
|---------|-------------|
| `toolkits add` | `--kind(-k) mcp\|python`, `--name(-n)`, `--description` *(all required)*, `--package`, `--package-root`, `--language(-l) node\|python`, `--command`, `--url(-u)`, `--transport streamable_http\|sse`, `--tools(-t) "*"`, `--app-id(-a)` (repeatable; key_value only for STDIO MCP), `--allowed-context` (remote: `tenant_id`/`agent_id`), `--tier small\|medium\|large` (python) |
| `toolkits import` | `--file(-f)` *(required — path to the MCP spec file)*, `--app-id(-a)` |
| `toolkits list` | `--verbose(-v)` |
| `toolkits export` | `--name(-n)`, `--output` |
| `toolkits remove` | `--name(-n)` |

```bash
# Local stdio MCP server from a package dir (inline config)
orchestrate toolkits add -k mcp -n math_toolkit --description "Factorial tools" \
  --package-root ./mcp_server --language node \
  --command '["node","dist/index.js","--transport","stdio"]' --tools "*"

# Remote MCP server
orchestrate toolkits add -k mcp -n remote_toolkit --description "Remote tools" \
  --url https://my-mcp.example.com --transport streamable_http --tools "tool_a,tool_b"

# From a saved MCP spec file
orchestrate toolkits import -f toolkits/math_toolkit.yaml
```

`--command` accepts a single command string or a JSON-style arg list.
`--tools` is comma-separated or `"*"` for all.

---

## knowledge-bases

| Command | Key options |
|---------|-------------|
| `knowledge-bases import` | `--file(-f)`, `--safe` |
| `knowledge-bases list` | `--verbose(-v)` |
| `knowledge-bases status` | `--name(-n)` / `--id(-i)` |
| `knowledge-bases export` | `--name(-n)`/`--id(-i)`, `--output(-o)` |
| `knowledge-bases remove` | `--name(-n)`/`--id(-i)` |

```bash
orchestrate knowledge-bases import -f knowledge_base/kb.yaml
orchestrate knowledge-bases status -n my_kb       # check ingestion/indexing
```

---

## connections

| Command | Key options |
|---------|-------------|
| `connections add` | `--app-id(-a)` *(required)*, `--component` (e.g. `knowledge`/`registry`), `--category` (e.g. `milvus`) |
| `connections configure` | *Required:* `--app-id(-a)`, `--environment`/`--env` `[draft\|live]`, `--type(-t)` `[member\|team]`, `--kind(-k)` `[basic\|bearer\|api_key\|key_value\|kv\|oauth_*_flow]`. *Optional:* `--server-url`/`--url(-u)`, `--sso(-s)`, `--idp-token-use`, `--idp-token-type`, `--idp-token-header`, `--app-token-header`, `--config-entries(-e)` |
| `connections set-credentials` | *Required:* `--app-id(-a)`, `--environment`/`--env`. *Creds (by kind):* `--username(-u)`, `--password(-p)`, `--token`, `--api-key(-k)`, `--entries(-e)` `k=v`, `--token-entries(-t)`, `--auth-entries`; OAuth: `--client-id`, `--client-secret`, `--token-url`, `--auth-url`, `--scope`, `--grant-type`, `--send-via [header\|body]` |
| `connections set-identity-provider` | `--idp-token-header`, `--idp-token-use`, `--idp-token-type`, `--app-token-header` |
| `connections import` | `--file(-f)` |
| `connections export` | `--output` |
| `connections list` | `--verbose(-v)` |
| `connections remove` | `--app-id(-a)` |

```bash
orchestrate connections add --app-id my_api
orchestrate connections configure -a my_api --kind api_key --type team --env draft
orchestrate connections set-credentials -a my_api --env draft --api-key "$MY_KEY"
orchestrate connections list
```

`--kind` (configure): `basic | bearer | api_key | key_value | kv |
oauth_auth_code_flow | oauth_auth_password_flow |
oauth_auth_client_credentials_flow | oauth_auth_on_behalf_of_flow |
oauth_auth_token_exchange_flow | oauth_auth_direct_access_flow`.
`--type`: `team` (shared) or `member` (per-user). `--env`: `draft` or `live`.

---

## models

| Command | Key options |
|---------|-------------|
| `models list` | list models available in the active env |
| `models import` | `--file(-f)` *(required)*, `--app-id(-a)` (a `key_value` connection with provider auth) |
| `models add` | `--name(-n)` *(required)*, `--description(-d)`, `--display-name`, `--provider-config` (JSON), `--app-id(-a)`, `--type [chat\|chat_vision\|completion\|embedding]` (default `chat`) |
| `models export` | `--name(-n)`, `--output(-o)` |
| `models remove` | `--name(-n)` |
| `models config` | tenant-level model selection subgroup: `list`, `default` (set default LLM), `denylist`, `reset`, `import`, `export` |
| `models policy` | routing pseudo-models across downstream models: `add`, `remove`, `import`, `export` |

```bash
orchestrate models list
orchestrate models import -f models/granite.yaml --app-id watsonx_credentials
orchestrate models config default          # set the tenant default LLM (was `models default` in older versions)
orchestrate models config list
```

---

## server — Developer Edition (local, Docker)

| Command | Key options |
|---------|-------------|
| `server start` | `--env-file(-e)`, `--with-langfuse(-l)`, `--with-ibm-telemetry(-i)`, `--with-doc-processing(-d)`, `--accept-terms-and-conditions` |
| `server stop` | — |
| `server reset` | wipe local tenant state |
| `server logs` | tail service logs |
| `server purge` | remove containers/volumes |
| `server edit` / `eject` / `ssh` / `attach-docker` / `release-docker` | advanced lifecycle |

```bash
orchestrate server start -e .env --accept-terms-and-conditions
orchestrate server logs
orchestrate server reset      # fresh local state
orchestrate server stop
```

---

## chat

| Command | Key options |
|---------|-------------|
| `chat start` | launch local chat UI |
| `chat ask <message>` | `--agent-name(-n)`, `--include-reasoning(-r)`, `--capture-logs(-l)`, `--thread-id(-t)` |
| `chat stop` | stop chat UI service |

```bash
orchestrate chat start
orchestrate chat ask -n weather_agent "What's the weather in Paris?" -r
orchestrate chat ask -n weather_agent "And tomorrow?" -t <thread_id>   # continue thread
```

---

## channels, evaluations, others

- **channels**: `create`, `delete`, `get`, `list`, `list-channels`, `import`, `export`, `webchat` — expose a deployed agent on a channel (e.g. embedded web chat). See `orchestrate channels webchat --help`.
- **evaluations**: `evaluate`, `quick-eval`, `generate`, `analyze`, `record`, `validate-native`, `validate-external`, `red-teaming` (see testing-debugging.md).
- **observability**: `traces` and related — inspect agent execution traces.
- **settings**: configure the active env, including observability/Langfuse tracing.
- **voice-configs** / **phone**: voice-enabled agents (`import`, `list`, `get`, `export`, `remove`). 2.11+ adds Deepgram **Flux** STT models (Flux General English is the new default).
- **partners**: catalog/offering publishing. **workspaces**: multi-workspace management.
