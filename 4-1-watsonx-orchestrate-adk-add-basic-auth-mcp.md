# 4-1. Add The Basic Auth MCP Server To `watsonx Orchestrate` *(Optional — Manual Configuration)*

> **This guide is optional.**
> It covers manual CLI steps for registering the Galaxium MCP server with
> `watsonx Orchestrate` using Basic Auth.
> If you prefer automation, skip to [4-1.8 Optional Automation Script](#4-18-optional-automation-script)
> or use Bob to perform these steps for you.

Use this guide after setting up the watsonx Orchestrate ADK in [3-watsonx-orchestrate-adk-setup.md](./3-watsonx-orchestrate-adk-setup.md).

For the local setup described in this repository, no `ngrok` or `localtunnel`
step is required.
The `watsonx Orchestrate` runtime runs inside a Lima VM and reaches the Galaxium MCP server
hosted on your machine through your local network IP address (`LOCAL_NET_IP`).

## 4-1.1 Start The Galaxium Basic Auth Infrastructure

Run these commands directly in your infrastructure terminal from the root of this repository.

### 1. Ensure The Infrastructure Repository Is Present

```sh
mkdir -p infrastructure
cd infrastructure
if [ ! -d "galaxium-travels-infrastructure-tsuedbro" ]; then
  git clone https://github.com/thomassuedbroecker/galaxium-travels-infrastructure-tsuedbro.git
fi
cd galaxium-travels-infrastructure-tsuedbro
git fetch --tags
git checkout v6.1.1
```

### 2. Stop Any Running OAuth2 Stack

Both stacks use port `8084`, so only one stack can run at a time:

```sh
docker compose -f local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml down --remove-orphans 2>/dev/null || true
```

### 3. Prepare The Environment File

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
```

Default credentials:
- Username: `demo-basic-user`
- Password: `demo-basic-password`

### 4. Start The Basic Auth Containers

Start the VM-compatible container stack (using `docker compose` or `podman compose`):

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  up -d --build
```

Verify that the MCP container is running and listening on port `8084`:

```sh
curl -i http://localhost:8084/health
```

Expected endpoints:
- Booking REST API: `http://localhost:8082/docs`
- REST web UI: `http://localhost:8083`
- MCP endpoint: `http://localhost:8084/mcp`

## 4-1.2 Open A New ADK Terminal

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

## 4-1.3 Create The Remote MCP Connection

```sh
export APP_ID="galaxium-mcp-remote-server"
orchestrate connections remove --app-id ${APP_ID}
orchestrate connections add --app-id ${APP_ID}
```

## 4-1.4 Configure The Connection

Two distinct URLs are used:

| Variable | Value | Purpose |
|----------|-------|---------|
| `MCP_REMOTE_BASE_SERVER_URL` | `http://<IP>:8084` | Connection credential — server root, no path |
| `MCP_REMOTE_SERVER_URL` | `http://<IP>:8084/mcp` | Toolkit import — full MCP endpoint |

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

## 4-1.5 Set The Basic Auth Credentials

```sh
export SERVICE_USERNAME="demo-basic-user"
export SERVICE_PASSWORD="demo-basic-password"
orchestrate connections set-credentials \
  --app-id ${APP_ID} \
  --environment ${ENVIRONMENT} \
  --username ${SERVICE_USERNAME} \
  --password ${SERVICE_PASSWORD}
```

## 4-1.6 Import The MCP Toolkit

This example imports `list_flights` first to keep the initial toolkit small.

```sh
export NAME="Galaxium-Travels-Booking-MCP-remote"
export DESCRIPTION="Galaxium Travels Booking MCP imported through Basic Auth."
export KIND="mcp"
export MCP_REMOTE_SERVER_URL="${MCP_REMOTE_BASE_SERVER_URL}/mcp"
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

## 4-1.7 Verify In LiteChat

If LiteChat is not already running:

```sh
orchestrate chat start
```

Open `http://localhost:3000/chat-lite` and verify that the imported toolkit is available
when you manage agents or tools.

## 4-1.8 Optional Automation Script

The folder also contains [`wxo_add_basic_auth_mcp_server.sh`](./watsonx-orchestrate-adk/wxo_add_basic_auth_mcp_server.sh), which automates the same
connection and toolkit-import flow.

For the OAuth 2.0 equivalent, see [4-2-watsonx-orchestrate-adk-add-oauth2-mcp.md](./4-2-watsonx-orchestrate-adk-add-oauth2-mcp.md).

### [Home](./README.md)
