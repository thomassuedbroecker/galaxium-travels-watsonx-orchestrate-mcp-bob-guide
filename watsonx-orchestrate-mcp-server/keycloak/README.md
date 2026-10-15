# Keycloak Configuration for watsonx Orchestrate Integration

This directory contains the OAuth 2.0 / Keycloak configuration tailored specifically for integrating the Galaxium Travels MCP server with **watsonx Orchestrate Developer Edition**.

---

## Why Is This Configuration Not Part of the Standalone Infrastructure?

When running the Galaxium Travels infrastructure alone (Step 1 or standalone development), Keycloak and the backends run on the host machine using default `localhost` addresses (`http://localhost:8086`, `http://localhost:8084`).

This configuration is maintained separately in this repository for the following architectural reasons:

1. **Network Topology & Virtual Machine Boundary:**
   - **watsonx Orchestrate Developer Edition** runs inside a virtualized environment (Lima VM) on its own isolated virtual network.
   - Inside the Lima VM, `localhost` (127.0.0.1) points to the VM itself, **not** to the host machine where Keycloak and the Galaxium containers are running.
   - To communicate across this VM boundary, watsonx Orchestrate must connect to the host's LAN IP address (`LOCAL_NET_IP`).

2. **Strict OpenID Connect Token Issuer (`iss`) Matching:**
   - Keycloak stamps its base URL into the token's `iss` (issuer) claim based on `--hostname` / `KEYCLOAK_PUBLIC_BASE_URL`.
   - The Galaxium MCP server validates that the incoming JWT bearer token's `iss` claim strictly matches `OIDC_ISSUER`.
   - If Keycloak is started with `http://localhost:8086`, but watsonx Orchestrate requests tokens from `http://${LOCAL_NET_IP}:8086`, Keycloak issues a token with `iss: http://localhost:8086/...`. When watsonx Orchestrate passes this token to the MCP server, the MCP server rejects it with:
     ```text
     401 Token validation failed: Invalid issuer
     ```
   - Therefore, Keycloak's public base URL, the MCP server's `OIDC_ISSUER`, and the watsonx Orchestrate `--token-url` must all be configured with the host's LAN IP (`http://${LOCAL_NET_IP}:8086`).

3. **Decoupling Core Infrastructure from Orchestrator-Specific Settings:**
   - The upstream Galaxium infrastructure repository remains independent, self-contained, and free of orchestrator-specific dependencies or hardcoded IP requirements.
   - Integration-specific settings (such as LAN IP overrides, dedicated `wxo-booking-mcp` clients, and `client_credentials` grant parameters) belong in the watsonx Orchestrate integration layer.

---

## Files in this Directory

| File | Purpose |
|---|---|
| [`apply_keycloak_wxo_config.sh`](./apply_keycloak_wxo_config.sh) | Helper script that detects host LAN IP and applies the configuration to the infrastructure folder. |
| [`realm/galaxium-realm.json`](./realm/galaxium-realm.json) | Keycloak realm definition with `sslRequired: "none"`, `implicitFlowEnabled: false`, and clients (`web-app-proxy`, `wxo-booking-mcp`, `booking-api`) equipped with the required `booking-api` audience mapper. |
| [`mcp.env.wxo-template`](./mcp.env.wxo-template) | Template for `mcp.env` with placeholders for binding `KEYCLOAK_PUBLIC_BASE_URL` and `MCP_PUBLIC_BASE_URL` to your host LAN IP. |

---

## Option A: Automated Configuration (Recommended)

From the root of this repository, run:

```sh
bash watsonx-orchestrate-mcp-server/keycloak/apply_keycloak_wxo_config.sh
```

This script:
1. Detects your host machine's LAN IP (`LOCAL_NET_IP`).
2. Clones the infrastructure repository if not present.
3. Generates `infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env` with the LAN IP URLs and points `KEYCLOAK_REALM_DIR` to this directory's realm definition.

Then start and verify the stack:

```sh
cd infrastructure/galaxium-travels-infrastructure-tsuedbro
docker compose -f local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml down --remove-orphans
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/start.sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/verify.sh
```

---

## Option B: Manual Configuration Steps

If you want to configure the Keycloak container manually step-by-step:

### Step 1: Obtain Host LAN IP

```sh
export LOCAL_NET_IP=$(ipconfig getifaddr en0)   # macOS
# Linux: export LOCAL_NET_IP=$(hostname -I | awk '{print $1}')
echo "Host LAN IP: ${LOCAL_NET_IP}"
```

### Step 2: Configure Environment File

In `infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/booking_system_mcp_oauth2_no_implicit_flow/`:

```sh
cd infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container/booking_system_mcp_oauth2_no_implicit_flow
cp mcp.env.template mcp.env
```

Edit `mcp.env` to update URLs and optionally mount this repository's realm:

```sh
export KEYCLOAK_PUBLIC_BASE_URL="http://${LOCAL_NET_IP}:8086"
export MCP_PUBLIC_BASE_URL="http://${LOCAL_NET_IP}:8084"
export KEYCLOAK_REALM_DIR="$(pwd)/../../../../watsonx-orchestrate-mcp-server/keycloak/realm"
export OIDC_CLIENT_ID="web-app-proxy"
export OIDC_CLIENT_SECRET="web-app-proxy-secret"
```

Or run `sed`:

```sh
sed -i.bak \
  "s|http://localhost:8086|http://${LOCAL_NET_IP}:8086|g; \
   s|http://localhost:8084|http://${LOCAL_NET_IP}:8084|g" \
  mcp.env
```

### Step 3: Recreate and Start Keycloak Container

Keycloak imports realm configuration at container creation time (`--import-realm`). To apply configuration changes, recreate the container:

```sh
docker compose -f docker_compose.yaml down --remove-orphans
bash start.sh
```

Wait ~30 seconds for Keycloak to finish importing the realm.

### Step 4: Verify Keycloak & Token Issuance

```sh
bash verify.sh
```

Check the OpenID discovery endpoint to confirm the issuer URL:

```sh
curl -s "http://${LOCAL_NET_IP}:8086/realms/galaxium/.well-known/openid-configuration" | grep issuer
```

Expected output:
```text
"issuer": "http://<LOCAL_NET_IP>:8086/realms/galaxium"
```
