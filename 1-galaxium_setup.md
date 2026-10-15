# 1. Set Up The Galaxium Travels Infrastructure

This repository keeps the walkthrough files at the root, but the runnable Galaxium
stack still comes from the separate infrastructure repository.

Use this guide to:

- clone that infrastructure repository into `./infrastructure/`
- start the **Basic Auth** stack used by guides `2-1` and `4-1`
- start the **OAuth2** stack used by guides `2-2` and `4-2`

## 1.1 Prerequisites

- Docker Desktop, Rancher Desktop, or another working Docker runtime
- `git`
- `curl` and `jq`
- `npx` if you plan to use MCP Inspector in guides `2-1` and `2-2`

## 1.2 Clone The Infrastructure Repository

This guide is written for **release `v6.1.1`** of the infrastructure repository.

From the root of this repository:

```sh
cd infrastructure
git clone https://github.com/thomassuedbroecker/galaxium-travels-infrastructure-tsuedbro.git
cd galaxium-travels-infrastructure-tsuedbro
git checkout v6.1.1
```

If you already cloned it earlier, just enter the directory and check out the release:

```sh
cd infrastructure/galaxium-travels-infrastructure-tsuedbro
git fetch --tags
git checkout v6.1.1
```

> **Note:** The OAuth2 stack used in guides `2-2` and `4-2` was introduced in `v6.1.0`.
> `v6.1.1` additionally fixes the OAuth metadata so MCP Inspector can log in (guide `2-2`).
> If you use a different tag the folder names and compose files may differ.

## 1.3. Basic Auth Stack For Guides 2 And 4-1

Use this stack when you want:

- the MCP backend protected by shared Basic Auth
- the manual backend verification from guide `2-1`
- the `watsonx Orchestrate` remote MCP import from guide `4-1`

### 1.3.1 Prepare The Env File

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
```

Default demo credentials:

- username: `demo-basic-user`
- password: `demo-basic-password`

### 1.3.2 Optional Smoke Checks

These scripts start their own short-lived test stacks and verify the current setup:

```sh
bash local-container/verify-basic-auth-backends.sh
bash local-container/verify-basic-auth-frontends-and-inspector.sh
```

### 1.3.3 Start The Running Basic Auth Stack

VM-style variant using the local network and not the host network.

Docker:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  up --build
```

Podman:

```sh
# If you hit docker-credential-osxkeychain errors, keep this DOCKER_CONFIG prefix.
DOCKER_CONFIG="$(mktemp -d)"
printf '{}' > "$DOCKER_CONFIG/config.json"
export DOCKER_CONFIG
podman compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  up --build
```

### 1.3.4 Basic Auth URLs

- Booking REST API docs: `http://localhost:8082/docs`
- REST web UI: `http://localhost:8083`
- MCP endpoint: `http://localhost:8084/mcp`
- MCP web UI: `http://localhost:8085`

## 1.4. OAuth2 Stack For Guide 4-2

Use this stack when you want:

- the MCP backend protected by **OAuth 2.0 `client_credentials` flow** via Keycloak
- the `watsonx Orchestrate` remote MCP import from guide `4-2`

> **Important:** watsonx Orchestrate does **not** support the OAuth2 implicit flow.
> This stack deliberately disables it in Keycloak and does not expose it in the MCP
> metadata. Only `client_credentials` (machine-to-machine) and `authorization_code`
> with PKCE (interactive MCP Inspector login) are allowed.

### 1.4.1 Prepare The Env File

```sh
cp local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env.template \
   local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env
```

For the **watsonx Orchestrate Developer Edition** setup you must replace `localhost` with
your host machine's LAN IP in `mcp.env`, because the wxO runtime runs inside a VM and
cannot reach `localhost`:

```sh
export LOCAL_NET_IP=$(ipconfig getifaddr en0)   # macOS
# Linux: export LOCAL_NET_IP=$(hostname -I | awk '{print $1}')

sed -i.bak \
  "s|http://localhost:8086|http://${LOCAL_NET_IP}:8086|g; \
   s|http://localhost:8084|http://${LOCAL_NET_IP}:8084|g" \
  local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env
```

Default demo credentials (from the Keycloak realm):

- Keycloak client ID: `web-app-proxy`
- Keycloak client secret: `web-app-proxy-secret`
- Token URL: `http://<LAN IP>:8086/realms/galaxium/protocol/openid-connect/token`

### 1.4.2 Start The OAuth2 Stack

```sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/start.sh
```

### 1.4.3 Verify The OAuth2 Stack

```sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/verify.sh
```

`verify.sh` checks that:

- every Keycloak client has `implicitFlowEnabled: false`
- a `client_credentials` token is issued correctly
- an MCP session opens with that token and `tools/list` returns the booking tools

### 1.4.4 OAuth2 URLs

- Keycloak admin console: `http://localhost:8086/admin` (user `admin` / `admin` — demo only)
- Keycloak token URL: `http://<LAN IP>:8086/realms/galaxium/protocol/openid-connect/token`
- MCP endpoint: `http://localhost:8084/mcp`
- MCP OAuth metadata: `http://localhost:8084/.well-known/oauth-protected-resource`

### 1.4.5 Stop The OAuth2 Stack

```sh
docker compose -f local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml down
```

### [Home](./README.md)
