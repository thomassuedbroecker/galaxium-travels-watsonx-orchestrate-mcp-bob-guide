# watsonx Orchestrate MCP Server

Installs and runs the [`ibm-watsonx-orchestrate-mcp-server`](https://pypi.org/project/ibm-watsonx-orchestrate-mcp-server/) — an MCP server that exposes watsonx Orchestrate agents, tools, toolkits, connections, and more as callable MCP tools over Streamable-HTTP or SSE transport.

Official documentation: <https://developer.watson-orchestrate.ibm.com/mcp_server/wxOmcp_installation>

---

## Prerequisites

- Python 3.11+
- A running watsonx Orchestrate Developer Edition instance
- The `watsonx-orchestrate-adk` environment configured and logged in (the MCP server uses the same credentials)

---

## 1. Virtual Environment Setup

```sh
cd watsonx-orchestrate-mcp-server
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
```

## 2. MCP Server Installation

```sh
pip install --upgrade ibm-watsonx-orchestrate-mcp-server
```

## 3. Environment Configuration

Copy the template and set the required values:

```sh
cp .env_template .env
```

Key variables in `.env`:

| Variable | Default | Description |
|---|---|---|
| `WXO_MCP_HOST` | LAN IP (`ipconfig getifaddr en0`) | Host the MCP server binds to |
| `WXO_MCP_PORT` | `8080` | Port the MCP server listens on |
| `WXO_MCP_TRANSPORT` | `http` | Transport: `http` (Streamable-HTTP), `sse`, or `stdio` |
| `WXO_MCP_WORKING_DIRECTORY` | `$(pwd)` | Working directory for file-based tool operations |

## 4. Start the MCP Server

Using the helper script (activates `.venv`, loads `.env`, then starts the server):

```sh
bash wxo_mcp_local_start.sh
```

Or manually:

```sh
source .venv/bin/activate
source .env
ibm-watsonx-orchestrate-mcp-server
```

The server starts on `http://<WXO_MCP_HOST>:<WXO_MCP_PORT>/mcp` (Streamable-HTTP) or `/sse` (SSE transport).

## 5. Verify the Server is Running

```sh
curl -s -o /dev/null -w "HTTP %{http_code}" http://127.0.0.1:8080/
```

A `404` response from the MCP server path confirms the server process is up and routing correctly.  
Use an MCP client or the [MCP Inspector](https://github.com/modelcontextprotocol/inspector) for a full handshake test:

```sh
npx @modelcontextprotocol/inspector
```

---

## Available MCP Tools

Once running, the server exposes the following tool groups:

| Group | Example tools |
|---|---|
| Agents | `list_agents`, `create_or_update_agent`, `import_agent`, `remove_agent`, `export_agent` |
| Tools | `list_tools`, `import_tool`, `create_tool`, `remove_tool`, `export_tool` |
| Toolkits | `list_toolkits`, `add_toolkit`, `import_toolkit`, `remove_toolkit`, `export_toolkit` |
| Connections | `list_connections`, `create_connection`, `configure_connection`, `set_credentials_connection` |
| Knowledge bases | `list_knowledge_bases`, `import_knowledge_bases`, `remove_knowledge_base` |
| Models | `list_models`, `import_model`, `create_or_update_model`, `remove_model` |
| Chat | `chat_with_agent` |

---

## watsonx Orchestrate Custom Explorer

The `watsonx_orchestrate_custom_explorer/` sub-directory contains a **Flask + D3.js v7** web application that connects to this MCP server and visualizes agents, tools, toolkits, and connections as an interactive force-directed dependency graph.

**Start this MCP server first** — the explorer calls it at runtime to fetch all data.

### Architecture

```
watsonx_orchestrate_custom_explorer/
├── .env_template       # WXO_MCP_BASE_URL, EXPLORER_PORT, EXPLORER_DEBUG
├── requirements.txt    # flask, flask-cors, python-dotenv
├── start.sh            # activates the parent .venv, installs deps, launches Flask
├── public/
│   ├── index.html      # dark-theme SPA (D3 v7 from jsDelivr CDN)
│   ├── styles.css      # responsive dark theme, no CSS framework
│   └── script.js       # D3 force simulation, sidebar, tabbed Listings drawer
└── src/
    ├── app.py          # Flask entry-point; REST API + static file serving
    ├── api.py          # MCP Streamable-HTTP client (asyncio.run per call)
    └── graph.py        # builds D3 {nodes, links} from agents/tools/toolkits/connections
```

### REST endpoints exposed by the explorer

| Endpoint | Description |
|---|---|
| `GET /` | Serves the SPA (`public/index.html`) |
| `GET /api/agents` | Live agent list from MCP `list_agents` |
| `GET /api/tools` | Live tool list from MCP `list_tools` |
| `GET /api/toolkits` | Live toolkit list from MCP `list_toolkits` |
| `GET /api/connections` | Live connection list from MCP `list_connections` |
| `GET /api/graph` | D3-ready `{nodes, links}` built from all four lists |
| `GET /api/health` | Socket reachability check for `WXO_MCP_BASE_URL` |

### Node kinds and colors

| Kind | Color | Source |
|---|---|---|
| Agent | `#4A90E2` | native / external / assistant agents |
| Tool | `#7ED321` | individual tools |
| Toolkit | `#F5A623` | MCP toolkits (group of tools) |
| Connection | `#BD10E0` | named connections |

See [`watsonx_orchestrate_custom_explorer/README.md`](watsonx_orchestrate_custom_explorer/README.md) for setup and usage.
