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
| Docker Desktop (or compatible runtime) | The Developer Edition runs as containers |
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

> **Tip:** This project was tested with `ibm-watsonx-orchestrate==2.12.0`.
> Pin that version if you need a reproducible environment:
> `python3 -m pip install ibm-watsonx-orchestrate==2.12.0`

---

## 3.4 Start Everything With The Automation Script

Once your `.env` is ready and the virtual environment exists, use the
helper script to bring up the full local stack in a single terminal:

```sh
cd watsonx-orchestrate-adk
bash wxo_local_start.sh
```

The script guides you through each step with coloured status messages.
Here is what it does, in order:

### Step 1 — Activate the Python virtual environment

```sh
source .venv/bin/activate
```

The `orchestrate` CLI and all Python dependencies are isolated inside
`.venv`. Activating it makes the `orchestrate` command available in the
current shell.

### Step 2 — Verify the ADK version

```sh
orchestrate --version
```

A quick sanity check to confirm the correct version is installed.

### Step 3 — Load environment variables

```sh
source .env
```

Reads your credentials and service passwords into the shell so every
subsequent `orchestrate` command can use them without you having to pass
flags manually.

### Step 4 — Reset the server configuration

```sh
orchestrate server reset
```

Clears any leftover server configuration from a previous run (cached
endpoints, tokens, etc.). The script then displays the resulting
`merged.env` file so you can inspect what was set, and waits for you
to press a key before continuing.

> The `merged.env` file is the internal config file that the Developer
> Edition writes to `~/.cache/orchestrate/`. It is deleted after you
> confirm so the next start uses a clean state.

### Step 5 — Start the Developer Edition containers

```sh
orchestrate server start \
  --env-file .env \
  --with-connections-ui \
  --accept-terms-and-conditions \
  --with-langfuse
```

This is the main startup command. It pulls (if needed) and starts all
the containers that make up the local platform:

| Flag | Purpose |
|---|---|
| `--env-file .env` | Passes your credentials and passwords to the containers |
| `--with-connections-ui` | Enables the connections management UI |
| `--accept-terms-and-conditions` | Non-interactive acceptance of the IBM terms |
| `--with-langfuse` | Starts Langfuse alongside the server for LLM call tracing |

> **What is Langfuse?**  
> Langfuse is an open-source LLM observability tool. When enabled it records
> every model call made by your agents so you can inspect prompts, responses,
> latency, and token counts. See <https://langfuse.com>.

### Step 6 — Wait for the server to become ready

The script polls `http://localhost:4321/api/v1/auth/token` every 5 seconds,
up to 5 attempts. When the endpoint responds the server is ready. If all
5 attempts fail the script asks whether you want to run `orchestrate server purge`
(which removes the containers and their data so you can start fresh).

### Step 7 — Activate the local environment

```sh
orchestrate env activate local
```

Tells the `orchestrate` CLI to point at your local Developer Edition
instance instead of any IBM Cloud environment. All subsequent commands
(model imports, agent imports, chat) operate on the local server.

> See the environments documentation:
> <https://developer.watson-orchestrate.ibm.com/getting_started/environments>

### Step 8 — List available models

```sh
orchestrate models list -a
```

Displays the models currently registered in your local instance. At this
point the list is likely empty — the next steps populate it.

### Step 9 — Create the watsonx.ai credentials connection

```sh
orchestrate connections add -a watsonx_credentials
orchestrate connections configure -a watsonx_credentials \
  --env draft -k key_value -t team
orchestrate connections set-credentials -a watsonx_credentials \
  --env draft -e "api_key=${WATSONX_APIKEY}"
```

A *connection* is how watsonx Orchestrate stores and uses external
credentials securely. These three commands create a connection named
`watsonx_credentials`, configure it as a team-scoped key-value store
in the `draft` environment, and inject your `WATSONX_APIKEY` into it.

> **Why a connection?**  
> Agents and models reference a connection by name instead of embedding
> credentials directly in their YAML files. This keeps secrets out of source
> control. See:
> <https://developer.watson-orchestrate.ibm.com/connections/overview>

### Step 10 — Generate model YAML files from templates

```sh
for template in ./model-configs/*.yaml_template; do
  yaml="${template%_template}"
  sed "s/YOUR_SPACE_ID/${WATSONX_SPACE_ID}/g" "$template" > "$yaml"
done
```

The model config templates in
[`watsonx-orchestrate-adk/model-configs/`](./watsonx-orchestrate-adk/model-configs/)
contain the placeholder `YOUR_SPACE_ID`. This loop replaces the placeholder
with your actual `WATSONX_SPACE_ID` and writes the final `.yaml` files.
The two templates produce:

- `model-config_llama_3_3_70b_instruct.yaml` — Meta Llama 3.3 70B Instruct
- `model-config_openai_gpt_oss_120b.yaml` — IBM Granite / GPT OSS 120B

### Step 11 — Import the models

```
orchestrate models import \
  --file ./model-configs/model-config_llama_3_3_70b_instruct.yaml \
  --app-id watsonx_credentials

orchestrate models import \
  --file ./model-configs/model-config_openai_gpt_oss_120b.yaml \
  --app-id watsonx_credentials
```

Registers the two watsonx.ai-hosted models in the local Developer Edition
so agents can reference them by name (e.g.
`watsonx/meta-llama/llama-3-3-70b-instruct`).

> See the model management documentation:
> <https://developer.watson-orchestrate.ibm.com/agents/models>

### Step 12 — Import the smoke-test agent

```
orchestrate agents import -f ./agents/agent_hello_world.yaml
```

Imports a minimal "hello world" agent defined in
[`watsonx-orchestrate-adk/agents/agent_hello_world.yaml`](./watsonx-orchestrate-adk/agents/agent_hello_world.yaml)
to verify that agent creation works end-to-end. The agent is backed by the
Llama 3.3 70B model and replies with a friendly greeting when you say hello.

### Step 13 — Start LiteChat

```
orchestrate chat start
```

Opens the LiteChat web interface at **`http://localhost:3000`**. This is
the built-in developer UI for chatting with your agents locally, without
needing the full watsonx Orchestrate cloud UI.

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
| `wxo_local_start_and_mcp_basic_auth.sh` | Same as above, also configures the MCP server with Basic Auth |
| `wxo_add_basic_auth_mcp_server.sh` | Adds a Basic Auth connection to an already-running MCP server |
| `get_ip-connection.sh` | Prints the local machine IP used for MCP server connections |

And in [`watsonx-orchestrate-mcp-server/`](./watsonx-orchestrate-mcp-server/):

| Script | Purpose |
|---|---|
| `wxo_mcp_local_start.sh` | Starts the watsonx Orchestrate MCP server in isolation |

---

### [Home](./README.md)
