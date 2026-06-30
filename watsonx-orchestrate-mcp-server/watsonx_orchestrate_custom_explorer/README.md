# watsonx Orchestrate Custom Explorer

A **Flask + D3.js v7** web application that connects to the `ibm-watsonx-orchestrate-mcp-server` and visualises agents, tools, toolkits, and connections as an interactive force-directed dependency graph.

---

## Prerequisites

- The `ibm-watsonx-orchestrate-mcp-server` is running (see the [parent README](../README.md))
- Python 3.11+ (uses the parent `.venv` — no separate virtual environment needed)

---

## Setup

### 1. Open a new terminal

The MCP server must keep running in its own terminal.

### 2. Copy and edit the environment file

```sh
cp watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer/.env_template \
   watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer/.env
```

| Variable | Default | Description |
|---|---|---|
| `WXO_MCP_BASE_URL` | `http://127.0.0.1:8080` | URL of the running MCP server |
| `EXPLORER_PORT` | `5001` | Port this Flask app listens on |
| `EXPLORER_DEBUG` | `false` | Set to `true` to enable Flask debug mode |

> `start.sh` automatically reads `WXO_MCP_HOST` and `WXO_MCP_PORT` from the parent `.env`
> and overrides `WXO_MCP_BASE_URL` when the MCP server is bound to a LAN IP.

### 3. Start the explorer

```sh
cd watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer
bash start.sh
```

`start.sh` activates the parent `watsonx-orchestrate-mcp-server/.venv` (which already contains the `mcp` SDK), installs the explorer's own dependencies (`flask`, `flask-cors`, `python-dotenv`) into that venv, then starts Flask.

### 4. Open the browser

```sh
open http://localhost:5001
```

---

## Features

| Feature | Description |
|---|---|
| **Force-directed graph** | D3 v7 simulation with zoom, pan, and drag. Nodes auto-cluster by kind. |
| **Node detail sidebar** | Click any node to inspect all its metadata. Arrays shown as pills; nested objects as formatted JSON. Sidebar is drag-resizable. |
| **Listings drawer** | `☰ Listings` opens a slide-in panel with four sortable, filterable tables — Agents, Tools, Toolkits, Connections. |
| **Focus node** | The *Focus* button in the Listings drawer pans and zooms the graph to centre the selected node. |
| **Live refresh** | `↻ Refresh` re-fetches all data from the MCP server without a page reload. |
| **Colour legend** | Agent `#4A90E2` · Tool `#7ED321` · Toolkit `#F5A623` · Connection `#BD10E0` |

---

## Architecture

```
watsonx_orchestrate_custom_explorer/
├── .env_template       # environment variable defaults
├── requirements.txt    # flask==3.0.0  flask-cors==4.0.0  python-dotenv>=1.1.0
├── start.sh            # venv activation + dep install + Flask launch
├── public/             # static frontend (served by Flask)
│   ├── index.html      # dark-theme SPA; D3 v7 loaded from jsDelivr CDN (SRI)
│   ├── styles.css      # responsive dark theme (--bg #0f1117), no CSS framework
│   └── script.js       # D3 force simulation, sidebar, Listings drawer
└── src/
    ├── app.py          # Flask entry-point: static serving + REST API routes
    ├── api.py          # MCP Streamable-HTTP client (asyncio.run per request)
    └── graph.py        # converts agent/tool/toolkit/connection lists → D3 graph
```

### REST API

| Endpoint | Description |
|---|---|
| `GET /` | SPA entry point |
| `GET /api/agents` | Live agent list (native + external + assistant) |
| `GET /api/tools` | Live tool list |
| `GET /api/toolkits` | Live toolkit list |
| `GET /api/connections` | Live connection list |
| `GET /api/graph` | D3-ready `{"nodes": [...], "links": [...]}` |
| `GET /api/health` | `{"status":"ok","mcp_url":"...","mcp_reachable":true/false}` |

### Graph edges

| Edge | Relation key | Meaning |
|---|---|---|
| agent → tool | `uses_tool` | agent has the tool in its tool list |
| agent → agent | `collaborates` | agent has the target as a collaborator |
| agent → connection | `uses_connection` | agent references the connection via `app_id` |
| toolkit → tool | `contains` | tool belongs to the toolkit |

---

## Dependencies

All open-source:

| Package | Licence | Purpose |
|---|---|---|
| [Flask 3.0](https://flask.palletsprojects.com/) | BSD-3-Clause | Web framework |
| [flask-cors 4.0](https://github.com/corydolphin/flask-cors) | MIT | CORS headers |
| [python-dotenv](https://github.com/theskumar/python-dotenv) | BSD-3-Clause | `.env` loading |
| [D3.js v7](https://d3js.org/) | ISC | Force-directed graph (CDN) |
| `mcp` (SDK) | Apache-2.0 | MCP client — inherited from parent `.venv` |
