# Labs with Bob

Three end-to-end labs that use **IBM Bob** to build, integrate, and visualise watsonx Orchestrate components on top of the Galaxium Travels application.

---

## Prerequisites

- IBM Bob is running with the **Galaxium Travels Developer** mode selected
- watsonx Orchestrate Developer Edition is running locally
- The Galaxium Travels infrastructure stack is up (containers running with the current network IP)
- The `watsonx-orchestrate-adk` and `watsonx-orchestrate-mcp-server` virtual environments and `.env` files are in place

---

## Lab 1 — Build a Booking Agent

**Goal:** Create a Galaxium Travels booking agent in watsonx Orchestrate that uses the Galaxium Travels MCP server to search flights and handle bookings.

### Steps

1. Select the **Galaxium Travels Developer** mode in Bob.
2. Open `prompts/prepared-initial-agent-prompt-for-bob.md` and paste its full contents into the Bob agentic dialog window.

Bob will automatically:
- Set up the agent configuration under `customization/configurations/agents/`
- Register the required MCP tools
- Verify authentication to the Galaxium Travels MCP server
- Configure the embedded agent for the Galaxium Travels UI (basic-auth setup)

---

## Lab 2 — Integrate the Agent into the Web App

**Goal:** Wire the new booking agent into the `galaxium-booking-web-app` frontend and restart the application stack.

### Prompt

Paste the following text into the Bob agentic dialog window:

---

```
Update the `infrastructure/galaxium-travels-infrastructure-tsuedbro/galaxium-booking-web-app`
to integrate the new agent in the application.
Use the `infrastructure/galaxium-travels-infrastructure-tsuedbro/local-container` folder.

Restart the Galaxium Travels application stack with:

docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  up --build
```

---

Bob will update the web app source, rebuild the containers, and verify the stack is running.

---

## Lab 3 — Build the watsonx Orchestrate Custom Explorer

**Goal:** Generate a Flask + D3.js v7 web application that connects to the `ibm-watsonx-orchestrate-mcp-server` and visualises agents, tools, toolkits, and connections as an interactive force-directed dependency graph.

The finished application lives in `watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer/`.  
See its [`README.md`](watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer/README.md) for setup and usage after generation.

### Prompt

Paste the following text into the Bob agentic dialog window:

---

```
Create the watsonx Orchestrate Custom Explorer application inside
watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer/.

The application is a Flask + D3.js v7 web UI that connects to the
ibm-watsonx-orchestrate-mcp-server (Streamable-HTTP transport) and
visualises agents, tools, toolkits, and connections as an interactive
force-directed dependency graph.

All libraries must be open-source (Flask, flask-cors, python-dotenv,
D3.js via jsDelivr CDN with SRI hash). No database is needed.

─── FOLDER STRUCTURE ──────────────────────────────────────────────────

watsonx_orchestrate_custom_explorer/
├── .env_template          # WXO_MCP_BASE_URL, EXPLORER_PORT, EXPLORER_DEBUG
├── requirements.txt       # flask==3.0.0  flask-cors==4.0.0  python-dotenv>=1.1.0
├── start.sh               # activates the PARENT watsonx-orchestrate-mcp-server/.venv,
│                          # installs requirements, resolves WXO_MCP_HOST from the
│                          # parent .env (eval of shell expressions), then runs
│                          # python3 src/app.py
├── README.md              # copy .env_template → .env, bash start.sh, open localhost:5001
├── public/
│   ├── index.html         # dark-theme SPA: header + sidebar + resize-handle +
│   │                      # SVG graph + slide-in Listings drawer
│   ├── styles.css         # dark theme (--bg #0f1117), fully responsive, no framework
│   └── script.js          # D3 force simulation, sidebar detail panel,
│                          # tabbed Listings drawer with sort/filter/focus-node,
│                          # sidebar drag-resize
└── src/
    ├── app.py             # Flask entry-point: serves public/, exposes
    │                      # /api/agents /api/tools /api/connections
    │                      # /api/toolkits /api/graph /api/health
    ├── api.py             # calls MCP tools via mcp.client.streamable_http
    │                      # (list_agents, list_tools, list_connections, list_toolkits)
    │                      # using asyncio.run(); parses TextContent blocks into list[dict]
    └── graph.py           # build_graph(agents, tools, connections, toolkits) → D3
                           # {nodes, links}; node kinds: agent/tool/toolkit/connection;
                           # colours: agent #4A90E2, tool #7ED321,
                           #         toolkit #F5A623, connection #BD10E0;
                           # edges: agent→tool (uses_tool), agent→collaborator (collaborates),
                           #        agent→connection (uses_connection),
                           #        toolkit→tool (contains)

─── src/api.py details ────────────────────────────────────────────────

• WXO_MCP_BASE_URL env var (default http://127.0.0.1:8080), path /mcp
• One async helper _async_call_tool that opens a fresh
  streamablehttp_client session per call (timeout 15 s)
• _parse_content handles both flat list and keyed-dict responses
  (agents → {native:[...], external:[...], assistant:[...]};
   connections → {non_configured:[...], draft:[...], live:[...]})
• /api/health does a socket.create_connection check on WXO_MCP_BASE_URL

─── start.sh details ──────────────────────────────────────────────────

• VENV_DIR = parent watsonx-orchestrate-mcp-server/.venv (SDK venv)
• Reads WXO_MCP_HOST and WXO_MCP_PORT from the parent .env using
  grep + eval so $(ipconfig getifaddr en0) style values are resolved;
  if RESOLVED_HOST differs from 127.0.0.1 it overrides WXO_MCP_BASE_URL
• Falls back to .env_template if no .env is found
• Runs on port EXPLORER_PORT (default 5001)

─── public/index.html details ─────────────────────────────────────────

• D3 v7.9.0 from cdn.jsdelivr.net with SRI hash
• Header: title + ↻ Refresh button + ☰ Listings button + status span
  + colour legend (Agent/Tool/Toolkit/Connection dots)
• Workspace: #sidebar (resizable) | #resize-handle | #graph-container > svg
• Listings drawer: right slide-in overlay with 4 tabs (Agents/Tools/
  Toolkits/Connections), search input, sortable table, expand-row JSON,
  "Focus" button that pans/zooms the graph to the matching node

─── public/script.js behaviour ────────────────────────────────────────

• On load: fetch /api/graph, /api/agents, /api/tools, /api/toolkits,
  /api/connections concurrently via Promise.all
• D3 forceSimulation with forceManyBody, forceLink, forceCenter,
  forceCollide; zoom/pan via d3.zoom
• Click a node → show detail card in sidebar (kind pill, metadata rows,
  array values as pills, nested objects as JSON pre block)
• Clicking a Listings row highlights it in the table; Focus button calls
  focusNode(id) which uses d3.zoom transform to centre the node
• Sidebar is drag-resizable (mousedown on #resize-handle)
• Escape key closes the drawer

Do NOT create node_modules, package.json, or any Node.js artefact.
Do NOT add a database.
Ensure all Python files import from the src/ directory correctly
(app.py adds its own directory to sys.path so api.py and graph.py are
importable as flat modules).
```
