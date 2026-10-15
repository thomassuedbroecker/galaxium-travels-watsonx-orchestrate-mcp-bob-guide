# 3. Set Up The `watsonx Orchestrate` ADK

Use this guide to prepare a local `watsonx Orchestrate Developer Edition`
environment. The quickest path is the automation script
[`watsonx-orchestrate-adk/wxo_local_start.sh`](./watsonx-orchestrate-adk/wxo_local_start.sh),
which runs all the steps in one terminal. The sections below explain each step
so you understand what is happening, even if you are new to watsonx Orchestrate.

Run all commands from the **repository root** unless a block says otherwise.

---

## 3.1 Prerequisites

| Requirement | Notes |
|---|---|
| Python `3.13` | Used to install the ADK CLI |
| Container runtime supported by the ADK (Lima VM is used here) | The Developer Edition runs as containers |
| `WO_ENTITLEMENT_KEY` | IBM entitlement key — grants access to the container images |
| `WATSONX_APIKEY` | IBM Cloud API key — used to call watsonx.ai models |
| `WATSONX_SPACE_ID` | Your watsonx.ai deployment space |

> **What is the Developer Edition?**  
> watsonx Orchestrate provides a lightweight local version of the platform
> called the *Developer Edition*. It runs entirely on your laptop inside
> containers, so you can build and test agents without needing a cloud
> subscription.  
> See the official docs:
> <https://developer.watson-orchestrate.ibm.com/getting_started/installing#ibm-cloud>

---

## 3.2 Create The Local `.env` File

Copy the template and fill in your credentials:

```sh
cp watsonx-orchestrate-adk/.env_template watsonx-orchestrate-adk/.env
```

Edit `watsonx-orchestrate-adk/.env` and replace every `<placeholder>`:

```sh
export WO_DEVELOPER_EDITION_SOURCE=myibm
export WO_ENTITLEMENT_KEY=<YOUR_ENTITLEMENT_KEY>
export WATSONX_APIKEY=<YOUR_WATSONX_API_KEY>
export WATSONX_SPACE_ID=<YOUR_SPACE_ID>
```

The file also contains service passwords for the internal components
(MinIO, Langfuse, PostgreSQL, etc.). The defaults work for local
development; change them only if you have a specific reason to.

Optional region settings (uncomment if you need a region other than `us-south`):

```sh
# export WATSONX_REGION=us-south
# export WATSONX_URL=https://${WATSONX_REGION}.ml.cloud.ibm.com
```

Reference material:

- Official installation guide:
  <https://developer.watson-orchestrate.ibm.com/getting_started/installing#ibm-cloud>
- Blog post (getting started walkthrough):
  <https://suedbroecker.net/2025/06/25/getting-started-with-local-ai-agents-in-the-watsonx-orchestrate-developer-edition/>

---

## 3.3 Create The Python Virtual Environment for the ADK

The ADK (Agent Development Kit) is the command-line tool `orchestrate` that
lets you start the server, import agents, manage models, and more.

```sh
cd watsonx-orchestrate-adk
python3.13 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install ibm-watsonx-orchestrate
orchestrate --version
```

> **Tip:** This project was tested with `ibm-watsonx-orchestrate==2.18.2`.
> Pin that version if you need a reproducible environment:
> `python3 -m pip install ibm-watsonx-orchestrate==2.18.2`

---

## 3.4 Start Everything With The Automation Script

Once your `.env` is ready and the virtual environment exists, use the
helper script to bring up the full local stack in a single terminal:

```sh
cd watsonx-orchestrate-adk
bash wxo_local_start.sh
```

The script guides you through each step with colored status messages.
Here is what it does, in order:

### Step 1 — Activate venv, load credentials, and verify version

```sh
source .venv/bin/activate
source .env
orchestrate --version
```

Activates the Python virtual environment so the `orchestrate` CLI is available,
reads your credentials and service passwords into the shell, then prints the
installed ADK version as a quick sanity check.

The script also warns if `OTEL_SERVICE_NAME` is not set in `.env`
(trace spans would then show `unknown_service`).

### Step 2 — Reset the server configuration

```sh
orchestrate server reset
```

Clears any leftover server configuration from a previous run (cached
endpoints, tokens, etc.).

### Step 3 — Start the Developer Edition containers

```sh
orchestrate server start \
  --env-file .env \
  --with-connections-ui \
  --accept-terms-and-conditions \
  --with-ibm-telemetry
```

This is the main startup command. It pulls (if needed) and starts all
the containers that make up the local platform:

| Flag | Purpose |
|---|---|
| `--env-file .env` | Passes your credentials and passwords to the containers |
| `--with-connections-ui` | Starts the Connections UI at **`http://localhost:3412/connectors`** for managing app credentials |
| `--accept-terms-and-conditions` | Non-interactive acceptance of the IBM terms |
| `--with-ibm-telemetry` | Starts Langfuse alongside the server for LLM call tracing |

> **Two UIs, two ports**
> `--with-connections-ui` starts the *connections management* UI (`:3412/connectors`) — used to manage app credentials.
> The *chat* UI (`:3000/chat-lite`) is a separate service started in step 7 below.

> **What is Langfuse?**
> Langfuse is an open-source LLM observability tool. When enabled it records
> every model call made by your agents so you can inspect prompts, responses,
> latency, and token counts. See <https://langfuse.com>.

### Step 4 — Wait for the server to become ready

The script polls the official readiness endpoint `http://localhost:4321/v1/health/ready`
every 10 seconds, up to 20 attempts (200 s). When the endpoint returns HTTP 200 the
server is ready. If all 20 attempts fail the script exits with a hint to run
`orchestrate server purge` (which removes the containers and their data so you
can start fresh).

> **Why 200 s?**
> The Developer Edition starts 42 containers (including Elasticsearch, OpenSearch,
> Milvus, Langfuse, and the wxO server itself) inside a Lima VM on arm64. On a
> typical MacBook with default Lima memory, all services need up to ~90–120 s to
> become healthy after the CLI exits.

### Step 5 — Activate the local environment and configure the watsonx.ai connection

```sh
orchestrate env activate local

orchestrate connections add -a watsonx_credentials 2>/dev/null || true
orchestrate connections configure -a watsonx_credentials --env draft -k key_value -t team
orchestrate connections set-credentials -a watsonx_credentials --env draft -e "api_key=${WATSONX_APIKEY}"
```

`orchestrate env activate local` tells the CLI to point at your local Developer
Edition instance instead of any IBM Cloud environment.

The three `connections` commands create a connection named `watsonx_credentials`,
configure it as a team-scoped key-value store in the `draft` environment, and
inject your `WATSONX_APIKEY` into it. Agents and models reference this connection
by name instead of embedding credentials directly in their YAML files.

> See the environments and connections documentation:
> <https://developer.watson-orchestrate.ibm.com/getting_started/environments>
> <https://developer.watson-orchestrate.ibm.com/connections/overview>

### Step 6 — Generate model YAMLs, import models, and import the smoke-test agent

```sh
# Expand templates
for tmpl in ./model-configs/*.yaml_template; do
  yaml="${tmpl%_template}"
  sed "s/YOUR_SPACE_ID/${WATSONX_SPACE_ID}/g" "$tmpl" > "$yaml"
done

# Import models
orchestrate models import --file ./model-configs/model-config_llama_3_3_70b_instruct.yaml --app-id watsonx_credentials
orchestrate models import --file ./model-configs/model-config_openai_gpt_oss_120b.yaml     --app-id watsonx_credentials

# Import hello-world agent
orchestrate agents import -f ./agents/agent_hello_world.yaml
```

The template loop replaces the `YOUR_SPACE_ID` placeholder with your actual
`WATSONX_SPACE_ID` and writes the final `.yaml` files. The two templates produce:

- `model-config_llama_3_3_70b_instruct.yaml` — Meta Llama 3.3 70B Instruct
- `model-config_openai_gpt_oss_120b.yaml` — OpenAI GPT OSS 120B

Both models are registered in the local Developer Edition so agents can reference
them by name (e.g. `watsonx/meta-llama/llama-3-3-70b-instruct`).

The hello-world agent in
[`watsonx-orchestrate-adk/agents/agent_hello_world.yaml`](./watsonx-orchestrate-adk/agents/agent_hello_world.yaml)
is a minimal smoke-test that confirms agent creation works end-to-end.

> See the model management documentation:
> <https://developer.watson-orchestrate.ibm.com/agents/models>

### Step 7 — Start the Chat UI

```sh
orchestrate chat start
```

The script runs this command automatically after importing the smoke-test agent.
It starts the LiteChat web interface and opens it at:

**`http://localhost:3000/chat-lite`**

This is the built-in developer UI for chatting with your agents locally,
without needing the full watsonx Orchestrate cloud UI.

> **Note:** `orchestrate chat start` starts the *chat* UI (`:3000/chat-lite`).
> It is separate from the Connections UI (`:3412/connectors`) started earlier by `--with-connections-ui`.

---

## 3.5 Optional Cleanup

If something goes wrong or you want a completely fresh start:

```sh
# Remove all containers and their data
orchestrate server purge
```

If you only want to reset the server configuration (keeps the containers):

```sh
orchestrate server reset
```

---

## 3.6 Other Helper Scripts

The [`watsonx-orchestrate-adk/`](./watsonx-orchestrate-adk/) folder also
contains these scripts for related tasks:

| Script | Purpose |
|---|---|
| `wxo_local_start.sh` | **This guide's primary script** — full local stack startup |
| `wxo_local_start_and_mcp_basic_auth.sh` | Variant of the startup flow that also configures the MCP server with Basic Auth (see script for its exact steps) |
| `wxo_add_basic_auth_mcp_server.sh` | Adds a Basic Auth connection to an already-running MCP server |
| `get_ip-connection.sh` | Prints the local machine IP used for MCP server connections |

And in [`watsonx-orchestrate-mcp-server/`](./watsonx-orchestrate-mcp-server/):

| Script | Purpose |
|---|---|
| `wxo_mcp_local_start.sh` | Starts the watsonx Orchestrate MCP server in isolation |

---

### [Home](./README.md)
