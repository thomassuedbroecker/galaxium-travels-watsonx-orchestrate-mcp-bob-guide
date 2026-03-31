# 2. Manually Verify The Basic Auth MCP Server

Use this guide after starting the Basic Auth stack from
[1-galaxium_setup.md](./1-galaxium_setup.md).

This guide talks directly to the MCP backend.
It does not go through the browser UIs.

The transport stays on `Streamable HTTP`.

## 2.1 What You Will Verify

- unauthenticated MCP access is rejected
- authenticated `initialize` succeeds
- authenticated `tools/list` succeeds
- authenticated `tools/call(list_flights)` succeeds

## 2.2 Prerequisites

- the Basic Auth stack is running on `http://localhost:8084/mcp`
- `curl`
- `jq`
- optional: `npx` if you want to open MCP Inspector UI after the commandline proof

## 2.3 Prepare The Working Folder

```sh
cd infrastructure/galaxium-travels-infrastructure-tsuedbro
cp local-container/basic-auth.env.template local-container/basic-auth.env
source local-container/basic-auth.env
```

Default credentials:

- username: `demo-basic-user`
- password: `demo-basic-password`

If the Basic Auth stack is not already running, start it now:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  up --build -d booking_system_mcp
```

Quick health check:

```sh
curl -fsS http://localhost:8084/ | head
```

## 2.4 Confirm That Unauthenticated MCP Access Fails

```sh
curl -i \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"manual-basic-check","version":"1.0.0"}}}'
```

Expected result:

- HTTP `401 Unauthorized`
- `WWW-Authenticate: Basic realm="Galaxium Booking MCP"`
- a response body similar to `{"detail":"Missing basic credentials"}`

## 2.5 Optional: Try MCP Inspector CLI

The direct Inspector CLI form against URL-based servers can still fail.
If you see `Arguments cannot be passed to a URL-based MCP server.`, use raw `curl`
or Inspector UI mode instead.

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --verbose
```

## 2.6 Build The Basic Auth Header

```sh
BASIC_TOKEN="$(printf '%s' "${BASIC_AUTH_USERNAME}:${BASIC_AUTH_PASSWORD}" | base64 | tr -d '\r\n')"
```

Optional check:

```sh
echo "Authorization: Basic ${BASIC_TOKEN}"
```

## 2.7 Run `initialize` With Basic Auth

```sh
curl -i \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"manual-basic-check","version":"1.0.0"}}}'
```

Expected result:

- HTTP `200`
- an `mcp-session-id` response header
- a response body containing `serverInfo`

Copy the returned session id into:

```sh
export SESSION_ID='<paste-the-mcp-session-id-here>'
```

## 2.8 Run `tools/list`

```sh
curl -sS \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "MCP-Session-Id: ${SESSION_ID}" \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

Expected tools:

- `list_flights`
- `book_flight`
- `get_bookings`
- `cancel_booking`
- `register_user`
- `get_user_id`

## 2.9 Run `tools/call(list_flights)`

```sh
curl -sS \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "MCP-Session-Id: ${SESSION_ID}" \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_flights","arguments":{}}}'
```

Expected result:

- HTTP `200`
- a payload with the available flights

## 2.10 Optional: Open MCP Inspector UI

```sh
export DANGEROUSLY_OMIT_AUTH=true   
npx @modelcontextprotocol/inspector
```

Use these Inspector settings:

- Connection mode: `Proxy`
- Transport: `Streamable HTTP`
- URL: `http://localhost:8084/mcp`
- Custom Header JSON:

```json
{"Authorization":"Basic YOUR_BASE64_TOKEN"}
```

Replace `YOUR_BASE64_TOKEN` with `${BASIC_TOKEN}`.

## 2.11 Stop The Basic Auth Stack

If you started the VM-style compose variant in this guide:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  down --remove-orphans
```

If you started the local-only compose variant instead, swap the compose file name.

## 2.12 Common Problems

- `401 Missing basic credentials`
  - the `Authorization: Basic ...` header was not sent
- `401` with a Basic header present
  - rebuild `BASIC_TOKEN` from the current `basic-auth.env` values
- `200` on `initialize`, but `tools/list` fails
  - reuse the exact `mcp-session-id` from the `initialize` response
- `localhost:8086` does not respond
  - that is expected in Basic Auth mode because Keycloak is not running
- `Arguments cannot be passed to a URL-based MCP server.`
  - use raw `curl` or Inspector UI mode instead of Inspector CLI mode

### [Home](./README.md)
