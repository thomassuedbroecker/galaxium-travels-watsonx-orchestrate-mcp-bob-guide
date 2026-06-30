"""
graph.py – converts raw MCP data into a D3-compatible node/link graph.

Node kinds:
  agent      – native / external / assistant agents
  tool       – individual tools
  toolkit    – MCP toolkits (groups of tools)
  connection – named connections

Edges:
  agent  → tool        (agent uses tool)
  agent  → toolkit     (agent uses toolkit)
  agent  → connection  (agent references connection via app_id)
  agent  → agent       (collaborator relationship)
  toolkit → tool       (toolkit contains tool)
"""

_KIND_COLORS = {
    "agent":      "#4A90E2",
    "tool":       "#7ED321",
    "toolkit":    "#F5A623",
    "connection": "#BD10E0",
}


def build_graph(agents: list, tools: list, connections: list, toolkits: list) -> dict:
    nodes: list[dict] = []
    links: list[dict] = []

    seen_ids: set[str] = set()

    def add_node(node_id: str, label: str, kind: str, meta: dict | None = None):
        if node_id in seen_ids:
            return
        seen_ids.add(node_id)
        nodes.append({
            "id":    node_id,
            "label": label,
            "kind":  kind,
            "color": _KIND_COLORS.get(kind, "#888888"),
            "meta":  meta or {},
        })

    def add_link(source: str, target: str, relation: str):
        if source in seen_ids and target in seen_ids:
            links.append({"source": source, "target": target, "relation": relation})

    # ── toolkits ─────────────────────────────────────────────────────────
    for tk in toolkits:
        tk_id = f"toolkit::{tk.get('name', 'unknown')}"
        add_node(tk_id, tk.get("name", "toolkit"), "toolkit", tk)

    # ── tools ─────────────────────────────────────────────────────────────
    for t in tools:
        name = t.get("name", "unknown")
        t_id = f"tool::{name}"
        add_node(t_id, name, "tool", t)
        # link tool → parent toolkit when the toolkit name is embedded
        tk_name = t.get("toolkit") or t.get("toolkit_name")
        if tk_name:
            tk_id = f"toolkit::{tk_name}"
            add_node(tk_id, tk_name, "toolkit")
            add_link(tk_id, t_id, "contains")

    # ── connections ───────────────────────────────────────────────────────
    for c in connections:
        name = c.get("name") or c.get("app_id", "unknown")
        c_id = f"connection::{name}"
        add_node(c_id, name, "connection", c)

    # ── agents ────────────────────────────────────────────────────────────
    for a in agents:
        name = a.get("name", "unknown")
        a_id = f"agent::{name}"
        add_node(a_id, name, "agent", a)

        # agent → tools it references
        for tool_name in a.get("tools") or []:
            t_id = f"tool::{tool_name}"
            add_node(t_id, tool_name, "tool")
            add_link(a_id, t_id, "uses_tool")

        # agent → collaborator agents
        for collab in a.get("collaborators") or []:
            c_id = f"agent::{collab}"
            add_node(c_id, collab, "agent")
            add_link(a_id, c_id, "collaborates")

        # agent → connection via app_id
        app_id = a.get("app_id")
        if app_id:
            conn_id = f"connection::{app_id}"
            add_node(conn_id, app_id, "connection")
            add_link(a_id, conn_id, "uses_connection")

    # second pass: add toolkit→tool links for tools now known
    for t in tools:
        tk_name = t.get("toolkit") or t.get("toolkit_name")
        if tk_name:
            tk_id = f"toolkit::{tk_name}"
            t_id = f"tool::{t.get('name', 'unknown')}"
            add_link(tk_id, t_id, "contains")

    return {"nodes": nodes, "links": links}
