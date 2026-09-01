# Local Environment — Configuration Reference

The local watsonx Orchestrate Developer Edition environment is activated with:

```sh
orchestrate env activate local
```

## Service Endpoints (default ports)

| Service               | URL                                   |
|-----------------------|---------------------------------------|
| LiteChat              | http://localhost:3000                 |
| Orchestrate API       | http://localhost:4321                 |
| Galaxium REST API     | http://localhost:8082/docs            |
| Galaxium REST Web UI  | http://localhost:8083                 |
| Galaxium MCP Server   | http://localhost:8084/mcp             |
| Galaxium MCP Web UI   | http://localhost:8085                 |

## Required Credentials

Set in `watsonx-orchestrate-adk/.env`:

| Variable                  | Description                              |
|---------------------------|------------------------------------------|
| `WO_ENTITLEMENT_KEY`      | IBM entitlement key for container images |
| `WATSONX_APIKEY`          | IBM Cloud API key                        |
| `WATSONX_SPACE_ID`        | watsonx.ai deployment space ID           |
| `WO_DEVELOPER_EDITION_SOURCE` | Set to `myibm`                       |
