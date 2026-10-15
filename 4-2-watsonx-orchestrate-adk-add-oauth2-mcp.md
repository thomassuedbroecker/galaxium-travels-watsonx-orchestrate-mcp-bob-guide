# 4-2. Add The OAuth2 MCP Server To `watsonx Orchestrate` *(Optional — Manual Configuration)*

> **This guide is optional.**
> It covers manual CLI steps for registering the Galaxium MCP server with
> `watsonx Orchestrate` using OAuth 2.0 `client_credentials` flow.
> If you prefer automation, skip to [4-2.9 Optional Automation Script](#4-29-optional-automation-script)
> or use Bob to perform these steps for you.

Use this guide after setting up the watsonx Orchestrate ADK in [3-watsonx-orchestrate-adk-setup.md](./3-watsonx-orchestrate-adk-setup.md).

For the Basic Auth equivalent, see [4-1-watsonx-orchestrate-adk-add-basic-auth-mcp.md](./4-1-watsonx-orchestrate-adk-add-basic-auth-mcp.md).

## Network Impact On Keycloak URLs & Token Validation

**Why does the network matter for Keycloak?**

- `watsonx Orchestrate Developer Edition` runs inside a Lima VM, whereas Keycloak and the Galaxium MCP server run in containers on your host machine.
- Inside the Lima VM, `localhost` points to the VM itself, not to your host machine. Therefore, watsonx Orchestrate must connect using your host machine's LAN IP address (`LOCAL_NET_IP`).
- **Token Issuer Claim (`iss`) Matching:** Keycloak stamps its base URL into the token's `iss` claim using its `--hostname` configuration (set via `KEYCLOAK_PUBLIC_BASE_URL`). The MCP server validates that the token's `iss` matches `OIDC_ISSUER`.
- If Keycloak is started with default `localhost:8086`, but watsonx Orchestrate requests tokens via `http://${LOCAL_NET_IP}:8086`, token validation fails with `401 Token validation failed: Invalid issuer`.
- **Requirement:** Before starting the OAuth2 stack, you must configure `mcp.env` with your host machine's `LOCAL_NET_IP` so that `KEYCLOAK_PUBLIC_BASE_URL`, `OIDC_ISSUER`, and the watsonx Orchestrate connection `--token-url` all match `http://${LOCAL_NET_IP}:8086`.
- **Why is this configuration maintained separately?** The standalone Galaxium infrastructure defaults to `localhost` for local host development. To keep the base infrastructure independent while providing a dedicated configuration for watsonx Orchestrate, integration templates and realm files are saved in [`watsonx-orchestrate-mcp-server/keycloak/`](./watsonx-orchestrate-mcp-server/keycloak/README.md).

## How OAuth2 Works In This Setup

This section explains the full token flow so you can understand what each CLI step
configures. The three systems involved are **Keycloak**, the **Galaxium MCP server**,
and **watsonx Orchestrate**.

```
watsonx Orchestrate runtime
        │
        │  1. POST /realms/galaxium/protocol/openid-connect/token
        │     grant_type=client_credentials
        │     client_id=web-app-proxy
        │     client_secret=web-app-proxy-secret
        ▼
   Keycloak :8086  (galaxium realm)
        │
        │  2. Returns JWT access token
        │     iss  = http://<LAN IP>:8086/realms/galaxium
        │     aud  = ["booking-api", "account"]
        │     azp  = web-app-proxy
        │
        ▼
watsonx Orchestrate runtime
        │
        │  3. POST /mcp
        │     Authorization: Bearer <access token>
        ▼
  Galaxium MCP server :8084  (AUTH_MODE=oauth2)
        │
        │  4. Validates token:
        │     - signature via OIDC_JWKS_URL (internal Keycloak)
        │     - iss  == OIDC_ISSUER (KEYCLOAK_PUBLIC_BASE_URL/realms/galaxium)
        │     - aud contains "booking-api"
        │     - exp not passed
        │
        │  5. Returns tools/list, tools/call results
        ▼
watsonx Orchestrate runtime
```

### Key constraints

> **watsonx Orchestrate does NOT support the OAuth2 implicit flow.**
> The Galaxium Keycloak realm has `implicitFlowEnabled: false` for every client.
> The MCP server does not advertise `token` in `response_types_supported`.
> Always use `oauth_auth_client_credentials_flow` as the connection `--kind`.

| Component | Relevant setting | Value used in this guide |
|-----------|-----------------|--------------------------|
| Keycloak realm | `implicitFlowEnabled` | `false` (enforced for all clients) |
| Keycloak client | grant | `client_credentials` only |
| Keycloak client | audience mapper | adds `booking-api` to `aud` |
| Galaxium MCP server | `AUTH_MODE` | `oauth2` |
| Galaxium MCP server | `OIDC_ISSUER` | `http://<LAN IP>:8086/realms/galaxium` |
| Galaxium MCP server | `OIDC_AUDIENCE` | `booking-api` |
| watsonx Orchestrate connection | `--kind` | `oauth_auth_client_credentials_flow` |
| watsonx Orchestrate connection | `--type` | `team` |

### References

- watsonx Orchestrate ADK — connections overview:
  <https://developer.watson-orchestrate.ibm.com/connections/overview>
- watsonx Orchestrate ADK — remote MCP toolkits:
  <https://developer.watson-orchestrate.ibm.com/tools/toolkits/remote_mcp_toolkits>
- watsonx Orchestrate ADK — building connections:
  <https://developer.watson-orchestrate.ibm.com/connections/build_connections>
- Keycloak configuration for this repository:
  [`infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/keycloak/README.md`](./infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/keycloak/README.md)
- OAuth2 MCP stack README:
  [`infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/booking_system_mcp_oauth2_no_implicit_flow/README.md`](./infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/booking_system_mcp_oauth2_no_implicit_flow/README.md)

## 4-2.1 Start The Galaxium OAuth2 Infrastructure

Run these commands directly in your infrastructure terminal from the root of this repository. You can use the automated configuration script or follow the manual steps below.

### Option A: Automated Configuration (Fastest)

```sh
# 1. Apply the watsonx Orchestrate Keycloak configuration
bash watsonx-orchestrate-mcp-server/keycloak/apply_keycloak_wxo_config.sh

# 2. Start and verify the stack
cd infrastructure/galaxium-travels-infrastructure-tsuedbro
docker compose -f local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml down --remove-orphans 2>/dev/null || true
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/start.sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/verify.sh
```

### Option B: Manual Configuration Steps

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

### 2. Stop Any Running Basic Auth Stack

Both stacks use port `8084`, so only one stack can run at a time:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  down --remove-orphans 2>/dev/null || true
```

### 3. Prepare The Environment File With Your Host LAN IP

Determine your host LAN IP and configure `mcp.env`:

```sh
export LOCAL_NET_IP=$(ipconfig getifaddr en0)   # macOS (or run: bash ../../watsonx-orchestrate-adk/get_ip-connection.sh)
# Linux: export LOCAL_NET_IP=$(hostname -I | awk '{print $1}')

echo "Using Host LAN IP: ${LOCAL_NET_IP}"

cp local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env.template \
   local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env

sed -i.bak \
  "s|http://localhost:8086|http://${LOCAL_NET_IP}:8086|g; \
   s|http://localhost:8084|http://${LOCAL_NET_IP}:8084|g" \
  local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env
```

### 4. Start The OAuth2 Stack

```sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/start.sh
```

Keycloak takes ~30 seconds on initial startup to import the realm.

### 5. Verify The OAuth2 Stack

```sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/verify.sh
```

Expected output confirms that `implicitFlowEnabled` is `false`, a `client_credentials` token is issued, and `tools/list` returns the booking tools.

## 4-2.2 Open A New ADK Terminal

```sh
cd watsonx-orchestrate-adk
source .venv/bin/activate
source .env
orchestrate env activate local
export LOCAL_NET_IP=$(ipconfig getifaddr en0)
echo "Keycloak token URL: http://${LOCAL_NET_IP}:8086/realms/galaxium/protocol/openid-connect/token"
echo "MCP booking server URL: http://${LOCAL_NET_IP}:8084/mcp"
```

If you want to inspect all local network interfaces first:

```sh
bash get_ip-connection.sh
```

## 4-2.3 Confirm The OAuth2 Stack Is Running

The MCP server must be running with `AUTH_MODE=oauth2` (started in guide 1, section 1.4)
before you import the toolkit, because the import step calls `tools/list` on the live server.

Quick check:

```sh
curl -s "http://localhost:8084/.well-known/oauth-protected-resource" | python3 -m json.tool
```

Expected: a JSON document containing `"resource"` and `"authorization_servers"` — and
`"response_types_supported": ["code"]` (no `"token"`, confirming implicit flow is disabled).

A bearer-less request must return `401`:

```sh
curl -i -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"check","version":"1.0.0"}}}'
```

Expected: `HTTP 401` with `WWW-Authenticate: Bearer`.

## 4-2.4 Create The Remote MCP Connection

```sh
export APP_ID="galaxium-mcp-oauth2-server"
orchestrate connections remove --app-id ${APP_ID}
orchestrate connections add --app-id ${APP_ID}
```

## 4-2.5 Configure The Connection

Two distinct URLs are used:

| Variable | Value | Purpose |
|----------|-------|---------|
| `MCP_REMOTE_BASE_SERVER_URL` | `http://<LAN IP>:8084` | Connection credential — server root, no path |
| `MCP_REMOTE_SERVER_URL` | `http://<LAN IP>:8084/mcp` | Toolkit import — full MCP endpoint |

```sh
export ENVIRONMENT="draft"
export TYPE="team"
export KIND="oauth_auth_client_credentials_flow"
export MCP_REMOTE_BASE_SERVER_URL="http://${LOCAL_NET_IP}:8084"
orchestrate connections configure \
  --app-id ${APP_ID} \
  --env ${ENVIRONMENT} \
  --kind ${KIND} \
  --type ${TYPE} \
  --url ${MCP_REMOTE_BASE_SERVER_URL}
```

> **Why `oauth_auth_client_credentials_flow`?**
> This is the machine-to-machine grant. watsonx Orchestrate posts the client ID and
> secret directly to Keycloak's token endpoint and attaches the resulting JWT as a
> `Bearer` token on every MCP request. No user browser session is required.
> The implicit flow (`oauth_auth_implicit_flow`) is **not supported** for Remote MCP
> toolkits — see the [connections overview](https://developer.watson-orchestrate.ibm.com/connections/overview#support-by-tool-type).

## 4-2.6 Set The OAuth2 Credentials

```sh
export OIDC_CLIENT_ID="web-app-proxy"
export OIDC_CLIENT_SECRET="web-app-proxy-secret"
export TOKEN_URL="http://${LOCAL_NET_IP}:8086/realms/galaxium/protocol/openid-connect/token"

orchestrate connections set-credentials \
  --app-id ${APP_ID} \
  --environment ${ENVIRONMENT} \
  --client-id ${OIDC_CLIENT_ID} \
  --client-secret ${OIDC_CLIENT_SECRET} \
  --token-url ${TOKEN_URL}
```

> **Token URL hostname must match `KEYCLOAK_PUBLIC_BASE_URL`.**
> Keycloak embeds the public hostname into the token's `iss` claim. The MCP server
> validates `iss` against `OIDC_ISSUER`, which is also set to `KEYCLOAK_PUBLIC_BASE_URL`.
> If you pass `localhost` here but the MCP stack was started with `LOCAL_NET_IP`, every
> token will be rejected with `Invalid issuer`. Always use the same LAN IP in both places.

The credentials are stored in
[`watsonx-orchestrate-adk/wxo_add_oauth2_mcp_server.sh`](./watsonx-orchestrate-adk/wxo_add_oauth2_mcp_server.sh)
for the automation variant. No credentials are committed to Git — they come from the
running environment or are set interactively.

## 4-2.7 Import The MCP Toolkit

```sh
export NAME="Galaxium-Travels-Booking-MCP-oauth2"
export DESCRIPTION="Galaxium Travels Booking MCP imported through OAuth2 client credentials."
export MCP_KIND="mcp"
export MCP_REMOTE_SERVER_URL="${MCP_REMOTE_BASE_SERVER_URL}/mcp"
export TRANSPORT="streamable_http"
export TOOLS="list_flights"

orchestrate toolkits remove --name ${NAME}
orchestrate toolkits add \
  --kind ${MCP_KIND} \
  --name ${NAME} \
  --description "${DESCRIPTION}" \
  --transport ${TRANSPORT} \
  --tools ${TOOLS} \
  --url ${MCP_REMOTE_SERVER_URL} \
  --app-id ${APP_ID}
```

Expected result:

```text
[INFO] - Successfully imported tool kit Galaxium-Travels-Booking-MCP-oauth2
```

> **Import calls `tools/list` on the live server.** If the OAuth2 stack is not running
> or the token URL is unreachable, the import will fail with an authentication error.
> Confirm section 4-2.3 passes before running this step.

## 4-2.8 Verify In LiteChat

If LiteChat is not already running:

```sh
orchestrate chat start
```

Open `http://localhost:3000/chat-lite` and verify that the imported toolkit is available
when you manage agents or tools.

## 4-2.9 Optional Automation Script

The folder also contains
[`wxo_add_oauth2_mcp_server.sh`](./watsonx-orchestrate-adk/wxo_add_oauth2_mcp_server.sh),
which automates the same connection and toolkit-import flow.

Run it from the `watsonx-orchestrate-adk` directory:

```sh
cd watsonx-orchestrate-adk
bash wxo_add_oauth2_mcp_server.sh
```

## 4-2.10 Dedicated Keycloak Client (Optional)

The demo client `web-app-proxy` works for local testing. For a cleaner setup, create a
dedicated client in Keycloak that allows only `client_credentials`. The full recipe is
in the Keycloak README:
[`local-container/keycloak/README.md` — Recipe: dedicated client for watsonx Orchestrate](./infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/keycloak/README.md#recipe-dedicated-client-for-watsonx-orchestrate).

After adding the client JSON to the realm, recreate the stack and re-run `verify.sh`,
then replace `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` in step 4-2.6 with the new values.

## 4-2.11 Common Problems

| Symptom | Cause | Fix |
|---------|-------|-----|
| `401 Token validation failed: Invalid issuer` | Token URL hostname ≠ `KEYCLOAK_PUBLIC_BASE_URL` | Use the same LAN IP in `--token-url` and in `mcp.env` |
| `401 Invalid audience` | Client has no `booking-api` audience mapper | Add the mapper from the Keycloak README |
| Import fails immediately after `start.sh` | Keycloak is still importing the realm | Wait ~30 s and retry |
| `orchestrate connections set-credentials` rejects `--token-url` | Older ADK version | Upgrade `ibm-watsonx-orchestrate` to `2.18.2` or later |
| LiteChat shows no tools | Toolkit imported before stack was ready | Re-run `orchestrate toolkits remove` + `orchestrate toolkits add` |

### [Home](./README.md)
