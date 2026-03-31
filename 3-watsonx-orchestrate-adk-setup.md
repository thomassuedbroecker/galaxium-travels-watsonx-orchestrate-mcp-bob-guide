# 3. Set Up The `watsonx Orchestrate` ADK

Use this guide to prepare a local `watsonx Orchestrate Development Edition`
environment that can later import the Galaxium MCP server.

Run the command blocks below from the repository root unless a block states
otherwise.

## 3.1 Prerequisites

- Python `3.13`
- Docker Desktop or another supported container runtime
- a valid `WO_ENTITLEMENT_KEY`
- a valid `WATSONX_APIKEY`
- a valid `WATSONX_SPACE_ID`

## 3.2 Create The Local `.env` File

```sh
cp watsonx-orchestrate-adk/.env_template watsonx-orchestrate-adk/.env
```

Edit `.env` and fill in the required values:

```sh
export WO_DEVELOPER_EDITION_SOURCE=myibm
export WO_ENTITLEMENT_KEY=<YOUR_ENTITLEMENT_KEY>
export WATSONX_APIKEY=<YOUR_WATSONX_API_KEY>
export WATSONX_SPACE_ID=<YOUR_SPACE_ID>
```

Optional region settings:

```sh
# export WATSONX_REGION=us-south
# export WATSONX_URL=https://${WATSONX_REGION}.ml.cloud.ibm.com
```

Reference material:

- IBM docs:
  <https://developer.watson-orchestrate.ibm.com/getting_started/installing#ibm-cloud>
- Blog post:
  <https://suedbroecker.net/2025/06/25/getting-started-with-local-ai-agents-in-the-watsonx-orchestrate-developer-edition/>

## 3.3 Create The Python Virtual Environment for the ADK

```sh
cd watsonx-orchestrate-adk
python3.13 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install ibm-watsonx-orchestrate==2.2.0
orchestrate --version
```

This repo currently pins `ibm-watsonx-orchestrate==2.2.0` and
`ibm-watsonx-orchestrate-mcp-server==2.2.0` because the workflow is tested
against that version pair.

## 3.4 Create The Python Virtual Environment for the MCP server

```sh
cd watsonx-orchestrate-mcp-server
cp .env_template .env
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install ibm-watsonx-orchestrate-mcp-server==2.2.0
#python3 -m pip install ibm-watsonx-orchestrate-mcp-server
source .env
echo "Configuration:"
echo "HOST:${WXO_MCP_HOST}"
echo "PORT:${WXO_MCP_PORT}"
echo "TRANSPORT:${WXO_MCP_TRANSPORT}"
echo "DIRECTORY:${WXO_MCP_WORKING_DIRECTORY}"
ibm-watsonx-orchestrate-mcp-server
```

This repo currently pins `ibm-watsonx-orchestrate==2.2.0` and
`ibm-watsonx-orchestrate-mcp-server==2.2.0` because the workflow is tested
against that version pair.

## 3.5 Optional Cleanup

If you want to remove an existing local runtime first:

```sh
orchestrate server purge
```

If you only want to reset the server configuration:

```sh
orchestrate server reset
```

## 3.6 Start Developer Edition

Open terminal `1`:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
orchestrate server start --env-file .env --with-connections-ui --accept-terms-and-conditions --with-langfuse
```

## 3.7 Activate The Local Environment And Start LiteChat

Open terminal `2`:

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
source .env
orchestrate env activate local
orchestrate chat start
```

LiteChat is available at `http://localhost:3000`.

## 3.8 Start The Local watsonx Orchestrate MCP Server

Open terminal `3`:

```sh
cd watsonx-orchestrate-mcp-server
source .venv/bin/activate
source .env
echo "HOST:${WXO_MCP_HOST}"
echo "PORT:${WXO_MCP_PORT}"
echo "TRANSPORT:${WXO_MCP_TRANSPORT}"
echo "DIRECTORY:${WXO_MCP_WORKING_DIRECTORY}"
ibm-watsonx-orchestrate-mcp-server
```

## 3.9 Helper Scripts In The Folders

The folder also contains helper scripts for the same local workflow:

- watsonx-orchestrate-adk
  - `get_ip-connection.sh`
  - `wxo_add_basic_auth_mcp_server.sh`
  - `wxo_local_start_and_mcp_basic_auth.sh`
  - `wxo_local_start.sh`

- watsonx-orchestrate-mcp-server
    - `wxo_mcp_local_start.sh`

The manual steps in this guide are the canonical documentation path.

### [Home](./README.md)
