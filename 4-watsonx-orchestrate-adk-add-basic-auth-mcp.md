# 4. Add The Basic Auth MCP Server To `watsonx Orchestrate`

Use this guide after:

- [1-galaxium_setup.md](./1-galaxium_setup.md) in Basic Auth mode
- [3-watsonx-orchestrate-adk-setup.md](./3-watsonx-orchestrate-adk-setup.md)

For the local setup described in this repository, no `ngrok` or `localtunnel`
step is required.
The `watsonx Orchestrate` runtime can reach the Galaxium MCP server through the
host IP address.

## 4.1 Open A New ADK Terminal

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
source .env
orchestrate env activate local
export LOCAL_NET_IP=$(ipconfig getifaddr en0)
echo "Remote MCP booking server URL: http://${LOCAL_NET_IP}:8084/mcp"
```

If you want to inspect all local network interfaces first:

```sh
bash get_ip-connection.sh
```

## 4.2. Create The Remote MCP Connection

```sh
export APP_ID="galaxium-mcp-remote-server"
orchestrate connections remove --app-id ${APP_ID}
orchestrate connections add --app-id ${APP_ID}
```

## 4.3 Configure The Connection

You need to understand there are two URLs the 

http://${LOCAL_NET_IP}:8084

```sh
export ENVIRONMENT="draft"
export TYPE="team"
export KIND="basic"
export MCP_REMOTE_BASE_SERVER_URL="http://${LOCAL_NET_IP}:8084"
orchestrate connections configure \
  --app-id ${APP_ID} \
  --env ${ENVIRONMENT} \
  --kind ${KIND} \
  --type ${TYPE} \
  --url ${MCP_REMOTE_BASE_SERVER_URL}
```

## 4.4 Set The Basic Auth Credentials

```sh
export SERVICE_USERNAME="demo-basic-user"
export SERVICE_PASSWORD="demo-basic-password"
orchestrate connections set-credentials \
  --app-id ${APP_ID} \
  --environment ${ENVIRONMENT} \
  --username ${SERVICE_USERNAME} \
  --password ${SERVICE_PASSWORD}
```

## 4.5 Import The MCP Toolkit

This example imports `list_flights` first to keep the initial toolkit small.

```sh
export NAME="Galaxium-Travels-Booking-MCP-remote"
export DESCRIPTION="Galaxium Travels Booking MCP imported through Basic Auth."
export KIND="mcp"
export MCP_REMOTE_SERVER_URL="${MCP_REMOTE_BASE_SERVER_URL}/mcp/"
export TRANSPORT="streamable_http"
export TOOLS="list_flights"

orchestrate toolkits remove --name ${NAME}
orchestrate toolkits add \
  --kind ${KIND} \
  --name ${NAME} \
  --description "${DESCRIPTION}" \
  --transport ${TRANSPORT} \
  --tools ${TOOLS} \
  --url ${MCP_REMOTE_SERVER_URL} \
  --app-id ${APP_ID}
```

If your local CLI does not accept `--app-id` on `toolkits add`, rerun the same
command without that flag.

Expected result:

```text
[INFO] - Successfully imported tool kit Galaxium-Travels-Booking-MCP-remote
```

## 4.6 Verify In LiteChat

If LiteChat is not already running:

```sh
orchestrate chat start
```

Open `http://localhost:3000` and verify that the imported toolkit is available
when you manage agents or tools.

## 4.7 Optional Automation Script

The folder also contains `wxo_wxomcp_basic_auth.sh`, which automates the same
connection and toolkit-import flow.

### [Home](./README.md)
