# Galaxium MCP Connection — Configuration Reference

This file documents the parameters used when registering the Galaxium Travels
Basic Auth MCP server as a watsonx Orchestrate connection.

The actual registration is performed by
`../../../customization/implementations/agents/deploy_agent.sh`.

## Connection Parameters

| Parameter       | Value                                      |
|-----------------|--------------------------------------------|
| `APP_ID`        | `galaxium-mcp-remote-server`               |
| `ENVIRONMENT`   | `draft`                                    |
| `KIND`          | `basic` (Basic Auth)                       |
| `TYPE`          | `team`                                     |
| `BASE_URL`      | `http://<LOCAL_NET_IP>:8084`               |
| `MCP_URL`       | `http://<LOCAL_NET_IP>:8084/mcp`           |
| `USERNAME`      | `demo-basic-user`                          |
| `PASSWORD`      | `demo-basic-password`                      |

> `LOCAL_NET_IP` is detected automatically via `ipconfig getifaddr en0`.

## Toolkit Parameters

| Parameter      | Value                                      |
|----------------|--------------------------------------------|
| `NAME`         | `Galaxium-Travels-Booking-MCP-remote`      |
| `KIND`         | `mcp`                                      |
| `TRANSPORT`    | `streamable_http`                          |
| `TOOLS`        | `list_flights,book_flight,get_bookings,cancel_booking,register_user,get_user_id` |

## Notes

- The base URL (no `/mcp` path) is used for the connection credential.
- The full MCP endpoint URL (with `/mcp` path) is used for the toolkit import.
- The `--app-id` flag on `orchestrate toolkits add` requires ADK ≥ 2.12.0.
  If the flag is rejected, remove it and the connection credential will be
  applied automatically.
