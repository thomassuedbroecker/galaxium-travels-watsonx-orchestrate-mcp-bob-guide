/**
 * script.js – watsonx Orchestrate Custom Explorer
 *
 * Features:
 *   • D3 v7 force-directed graph with drag, zoom, click-to-inspect
 *   • Resizable left sidebar (drag handle)
 *   • Listings drawer (slide-in from right) with per-tab tables,
 *     full-text filter, sortable columns, and expandable row detail
 *
 * Runtime dependency: D3.js v7 (ISC) – loaded via <script> in index.html.
 * No other external libraries.
 */

"use strict";

// ── constants ─────────────────────────────────────────────────────────────────

const API_BASE = "";

const KIND_COLOR = {
  agent:      "#4A90E2",
  tool:       "#7ED321",
  toolkit:    "#F5A623",
  connection: "#BD10E0",
};

// Keys shown in the card header – skip from the detail rows
const HEADER_KEYS = new Set(["name", "id", "kind", "color", "label"]);

// ── DOM refs ──────────────────────────────────────────────────────────────────

const STATUS       = document.getElementById("status-msg");
const SIDEBAR      = document.getElementById("sidebar-content");
const HINT         = document.getElementById("sidebar-hint");
const HANDLE       = document.getElementById("resize-handle");
const SIDEBAR_EL   = document.getElementById("sidebar");
const WORKSPACE    = document.getElementById("workspace");
const GRAPH_CT     = document.getElementById("graph-container");

const DRAWER       = document.getElementById("drawer");
const OVERLAY      = document.getElementById("drawer-overlay");
const BTN_LISTINGS = document.getElementById("btn-listings");
const BTN_CLOSE    = document.getElementById("drawer-close");
const SEARCH_IN    = document.getElementById("drawer-search");
const DRAWER_BODY  = document.getElementById("drawer-body");
const TAB_BTNS     = Array.from(document.querySelectorAll(".tab-btn"));

// ── app state ─────────────────────────────────────────────────────────────────

// raw data cache (populated on refresh)
const DATA = { agents: [], tools: [], toolkits: [], connections: [] };

// drawer state
let activeTab    = "agents";
let sortCol      = "name";
let sortAsc      = true;
let filterText   = "";
let expandedRow  = null;   // index of expanded table row

// graph state
let simulation, svg, linkGroup, nodeGroup, linkSel;
let zoomBehaviour = null;   // D3 zoom instance, kept for programmatic pan/zoom
let simNodeCache  = [];     // live sim nodes (with x/y), updated after each render

// ── status helper ─────────────────────────────────────────────────────────────

function setStatus(msg, isError = false) {
  STATUS.textContent = msg;
  STATUS.style.color = isError ? "#f87171" : "#94a3b8";
}

// ── sidebar resize ────────────────────────────────────────────────────────────

(function initResize() {
  let dragging = false;
  let startX   = 0;
  let startW   = 0;

  HANDLE.addEventListener("mousedown", e => {
    dragging = true;
    startX   = e.clientX;
    startW   = SIDEBAR_EL.getBoundingClientRect().width;
    HANDLE.classList.add("dragging");
    SIDEBAR_EL.style.transition = "none";   // disable CSS transition while dragging
    document.body.style.cursor  = "col-resize";
    document.body.style.userSelect = "none";
    e.preventDefault();
  });

  document.addEventListener("mousemove", e => {
    if (!dragging) return;
    const delta  = e.clientX - startX;
    const newW   = Math.max(180, Math.min(startW + delta, WORKSPACE.clientWidth * 0.6));
    SIDEBAR_EL.style.width = newW + "px";
    // let the graph fill the rest – no explicit width needed (flex:1)
    if (simulation) simulation.alpha(0.1).restart(); // nudge simulation on resize
  });

  document.addEventListener("mouseup", () => {
    if (!dragging) return;
    dragging = false;
    HANDLE.classList.remove("dragging");
    SIDEBAR_EL.style.transition = "";
    document.body.style.cursor  = "";
    document.body.style.userSelect = "";
  });

  // touch support
  HANDLE.addEventListener("touchstart", e => {
    startX = e.touches[0].clientX;
    startW = SIDEBAR_EL.getBoundingClientRect().width;
    SIDEBAR_EL.style.transition = "none";
    e.preventDefault();
  }, { passive: false });

  document.addEventListener("touchmove", e => {
    const delta = e.touches[0].clientX - startX;
    const newW  = Math.max(180, Math.min(startW + delta, WORKSPACE.clientWidth * 0.6));
    SIDEBAR_EL.style.width = newW + "px";
  });

  document.addEventListener("touchend", () => {
    SIDEBAR_EL.style.transition = "";
  });
})();

// ── detail sidebar (node click) ───────────────────────────────────────────────

function renderSidebar(node) {
  HINT.style.display = "none";
  const meta = node.meta || {};

  const header = `
    <div class="detail-card-header">
      <span class="detail-card-dot" style="background:${esc(node.color || '#888')}"></span>
      <span class="detail-card-name">${esc(node.label)}</span>
      <span class="detail-kind-pill" style="background:${esc(node.color || '#888')}">${esc(node.kind)}</span>
    </div>`;

  const rows = Object.entries(meta)
    .filter(([k]) => !HEADER_KEYS.has(k))
    .map(([k, v]) => `
      <div class="detail-row">
        <div class="detail-label">${esc(humanLabel(k))}</div>
        <div class="detail-value">${renderValue(v)}</div>
      </div>`)
    .join("");

  SIDEBAR.innerHTML = `
    <div class="detail-card">
      ${header}
      <div class="detail-rows">${rows ||
        '<div class="detail-row"><div class="detail-label">—</div>' +
        '<div class="detail-value" style="color:var(--muted)">No metadata</div></div>'}
      </div>
    </div>`;
}

function humanLabel(key) {
  return key.replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2")
            .replace(/\b\w/g, c => c.toUpperCase());
}

function renderValue(v) {
  if (v === null || v === undefined) return '<span style="color:var(--muted)">—</span>';
  if (Array.isArray(v)) {
    if (!v.length) return '<span style="color:var(--muted)">—</span>';
    return v.map(i => `<span class="detail-pill">${esc(String(i))}</span>`).join("");
  }
  if (typeof v === "object")
    return `<code class="detail-json">${esc(JSON.stringify(v, null, 2))}</code>`;
  if (typeof v === "boolean") {
    const c = v ? "#7ED321" : "#f87171";
    return `<span style="color:${c};font-weight:600">${v ? "Yes" : "No"}</span>`;
  }
  const s = String(v);
  return s === "" ? '<span style="color:var(--muted)">—</span>' : esc(s);
}

function esc(str) {
  return String(str)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// ── graph ─────────────────────────────────────────────────────────────────────

function initSvg() {
  const w = GRAPH_CT.clientWidth;
  const h = GRAPH_CT.clientHeight;

  d3.select("#graph").selectAll("*").remove();

  zoomBehaviour = d3.zoom().scaleExtent([0.15, 5])
    .on("zoom", ev => {
      linkGroup.attr("transform", ev.transform);
      nodeGroup.attr("transform", ev.transform);
    });

  svg = d3.select("#graph")
    .attr("viewBox", [0, 0, w, h])
    .call(zoomBehaviour);

  svg.append("defs").append("marker")
    .attr("id", "arrow").attr("viewBox", "0 -5 10 10")
    .attr("refX", 22).attr("refY", 0)
    .attr("markerWidth", 6).attr("markerHeight", 6)
    .attr("orient", "auto")
    .append("path").attr("d", "M0,-5L10,0L0,5").attr("fill", "#4a5568");

  linkGroup = svg.append("g").attr("class", "links");
  nodeGroup = svg.append("g").attr("class", "nodes");
  return { w, h };
}

function renderGraph(data) {
  const nodes = data.nodes || [];
  const links = data.links || [];

  if (!nodes.length) { setStatus("No data returned from MCP server.", true); return; }
  setStatus(`${nodes.length} nodes · ${links.length} edges`);

  const { w, h } = initSvg();

  const simNodes = nodes.map(n => ({ ...n }));
  const byId     = Object.fromEntries(simNodes.map(n => [n.id, n]));
  const simLinks = links
    .filter(l => byId[l.source] && byId[l.target])
    .map(l => ({ ...l, source: byId[l.source], target: byId[l.target] }));

  simulation = d3.forceSimulation(simNodes)
    .force("link",    d3.forceLink(simLinks).id(d => d.id).distance(110))
    .force("charge",  d3.forceManyBody().strength(-320))
    .force("center",  d3.forceCenter(w / 2, h / 2))
    .force("collide", d3.forceCollide(26));

  linkSel = linkGroup.selectAll(".link")
    .data(simLinks).join("line")
      .attr("class", "link")
      .attr("marker-end", "url(#arrow)");

  const nodeSel = nodeGroup.selectAll(".node")
    .data(simNodes).join("g")
      .attr("class", "node")
      .call(
        d3.drag()
          .on("start", (ev, d) => { if (!ev.active) simulation.alphaTarget(0.3).restart(); d.fx=d.x; d.fy=d.y; })
          .on("drag",  (ev, d) => { d.fx=ev.x; d.fy=ev.y; })
          .on("end",   (ev, d) => { if (!ev.active) simulation.alphaTarget(0); d.fx=null; d.fy=null; })
      )
      .on("click", (ev, d) => {
        nodeGroup.selectAll(".node").classed("selected", false);
        d3.select(ev.currentTarget).classed("selected", true);
        linkSel.classed("highlighted", l => l.source.id===d.id || l.target.id===d.id);
        renderSidebar(d);
        ev.stopPropagation();
      });

  svg.on("click", () => {
    nodeGroup.selectAll(".node").classed("selected", false);
    linkSel.classed("highlighted", false);
    HINT.style.display = "";
    SIDEBAR.innerHTML = "";
  });

  nodeSel.append("circle")
    .attr("r",    d => nodeRadius(d))
    .attr("fill", d => d.color || "#888");

  nodeSel.append("text")
    .attr("dy", d => nodeRadius(d) + 13)
    .attr("text-anchor", "middle")
    .text(d => truncate(d.label, 20));

  simulation.on("tick", () => {
    linkSel
      .attr("x1", d => d.source.x).attr("y1", d => d.source.y)
      .attr("x2", d => d.target.x).attr("y2", d => d.target.y);
    nodeSel.attr("transform", d => `translate(${d.x},${d.y})`);
  });

  // keep a live reference so focusNode() can look up x/y after settling
  simNodeCache = simNodes;
}

// ── focus a node programmatically (called from listing rows) ─────────────────

/**
 * Select the graph node whose id equals nodeId, highlight its links,
 * populate the detail sidebar, and smoothly pan+zoom the SVG to centre it.
 */
function focusNode(nodeId) {
  if (!svg || !nodeGroup || !linkSel) return;

  // find the sim node with matching id
  const target = simNodeCache.find(n => n.id === nodeId);
  if (!target) return;

  // select + highlight – reuse the same logic as a click
  nodeGroup.selectAll(".node").classed("selected", false);
  nodeGroup.selectAll(".node")
    .filter(d => d.id === nodeId)
    .classed("selected", true);

  linkSel.classed("highlighted", l =>
    l.source.id === nodeId || l.target.id === nodeId
  );

  renderSidebar(target);

  // smooth pan + zoom to centre the node
  const w       = GRAPH_CT.clientWidth;
  const h       = GRAPH_CT.clientHeight;
  const scale   = 1.6;                          // zoom-in level on focus
  const tx      = w / 2 - target.x * scale;
  const ty      = h / 2 - target.y * scale;
  const transform = d3.zoomIdentity.translate(tx, ty).scale(scale);

  svg.transition().duration(600)
    .call(zoomBehaviour.transform, transform);
}

// ── derive graph node id from a listing row ───────────────────────────────────

function graphNodeId(tab, row) {
  // node IDs in graph.py are built as "<kind>::<name-or-app_id>"
  const kindMap = { agents: "agent", tools: "tool", toolkits: "toolkit", connections: "connection" };
  const kind    = kindMap[tab] || tab.replace(/s$/, "");
  const name    = row.name || row.app_id || "";
  return `${kind}::${name}`;
}

function nodeRadius(d) {
  return { agent: 16, toolkit: 14, connection: 12, tool: 10 }[d.kind] ?? 10;
}

function truncate(s, n) {
  return s && s.length > n ? s.slice(0, n - 1) + "…" : s;
}

// ── drawer ────────────────────────────────────────────────────────────────────

function openDrawer()  { DRAWER.classList.add("open"); OVERLAY.classList.add("open"); SEARCH_IN.focus(); }
function closeDrawer() { DRAWER.classList.remove("open"); OVERLAY.classList.remove("open"); }

BTN_LISTINGS.addEventListener("click", openDrawer);
BTN_CLOSE.addEventListener("click", closeDrawer);
OVERLAY.addEventListener("click", closeDrawer);
document.addEventListener("keydown", e => { if (e.key === "Escape") closeDrawer(); });

TAB_BTNS.forEach(btn => btn.addEventListener("click", () => {
  activeTab = btn.dataset.tab;
  sortCol   = "name";
  sortAsc   = true;
  filterText = "";
  SEARCH_IN.value = "";
  expandedRow = null;
  TAB_BTNS.forEach(b => b.classList.toggle("active", b === btn));
  renderTable();
}));

SEARCH_IN.addEventListener("input", () => {
  filterText  = SEARCH_IN.value.toLowerCase();
  expandedRow = null;
  renderTable();
});

// ── table rendering ───────────────────────────────────────────────────────────

// Schema per tab: array of { key, label }
const TAB_SCHEMA = {
  agents:      [{ key: "name", label: "Name" }, { key: "kind", label: "Kind" }, { key: "llm", label: "LLM" }, { key: "style", label: "Style" }],
  tools:       [{ key: "name", label: "Name" }, { key: "description", label: "Description" }],
  toolkits:    [{ key: "name", label: "Name" }, { key: "description", label: "Description" }],
  connections: [{ key: "app_id", label: "App ID" }, { key: "auth_type", label: "Auth" }, { key: "type", label: "Type" }, { key: "credentials_set", label: "Credentials" }],
};

// For connections the primary display key is app_id, not name
const TAB_PRIMARY = { agents: "name", tools: "name", toolkits: "name", connections: "app_id" };

function getRows() {
  const raw     = DATA[activeTab] || [];
  const primary = TAB_PRIMARY[activeTab];
  // filter
  const filtered = filterText
    ? raw.filter(r => JSON.stringify(r).toLowerCase().includes(filterText))
    : raw;
  // sort
  return filtered.slice().sort((a, b) => {
    const va = String(a[sortCol] ?? a[primary] ?? "").toLowerCase();
    const vb = String(b[sortCol] ?? b[primary] ?? "").toLowerCase();
    return sortAsc ? va.localeCompare(vb) : vb.localeCompare(va);
  });
}

function renderTable() {
  const schema  = TAB_SCHEMA[activeTab] || [];
  const rows    = getRows();
  const primary = TAB_PRIMARY[activeTab];
  const color   = KIND_COLOR[activeTab.replace(/s$/, "")] || "#888";

  if (!rows.length) {
    DRAWER_BODY.innerHTML = `<div class="drawer-empty">${
      filterText ? "No results match your filter." : "No data available."
    }</div>`;
    return;
  }

  // sortable column headers + a non-sortable "Focus" column at the end
  const thCells = schema.map(col => {
    const isSorted = sortCol === col.key;
    const icon     = isSorted ? (sortAsc ? "▲" : "▼") : "⇅";
    return `<th data-col="${esc(col.key)}" class="${isSorted ? "sorted" : ""}">
      ${esc(col.label)}<span class="sort-icon">${icon}</span>
    </th>`;
  }).join("") + `<th class="th-focus" title="Focus in diagram">⊙</th>`;

  const colSpan = schema.length + 1;   // +1 for focus column

  const bodyRows = rows.map((row, idx) => {
    const isExpanded = expandedRow === idx;
    const nodeId     = graphNodeId(activeTab, row);
    // only show the focus button when the node exists in the graph
    const inGraph    = simNodeCache.some(n => n.id === nodeId);

    const tdCells = schema.map(col => {
      const v   = row[col.key];
      const cls = col.key === primary ? "td-name" : "";
      let display;
      if (col.key === "kind") {
        display = `<span class="kind-badge" style="background:${color}">${esc(String(v ?? ""))}</span>`;
      } else if (typeof v === "boolean") {
        const c = v ? "#7ED321" : "#f87171";
        display = `<span style="color:${c};font-weight:600">${v ? "Yes" : "No"}</span>`;
      } else if (Array.isArray(v)) {
        display = v.length ? v.map(i => `<span class="detail-pill">${esc(String(i))}</span>`).join("") : '<span style="color:var(--muted)">—</span>';
      } else {
        display = esc(String(v ?? "—"));
      }
      return `<td class="${cls}">${display}</td>`;
    }).join("");

    // focus button cell — data-nodeid carries the graph id
    const focusCell = inGraph
      ? `<td class="td-focus"><button class="btn-focus-node" data-nodeid="${esc(nodeId)}" title="Focus in diagram">⊙ Focus</button></td>`
      : `<td class="td-focus"></td>`;

    const expandClass = isExpanded ? " selected" : "";
    const detailHtml  = isExpanded
      ? `<tr class="row-detail-tr"><td colspan="${colSpan}" class="row-detail open">
           <pre>${esc(JSON.stringify(row, null, 2))}</pre>
         </td></tr>`
      : "";

    return `<tr data-idx="${idx}" class="${expandClass}">${tdCells}${focusCell}</tr>${detailHtml}`;
  }).join("");

  DRAWER_BODY.innerHTML = `
    <table class="list-table">
      <thead><tr>${thCells}</tr></thead>
      <tbody>${bodyRows}</tbody>
    </table>`;

  // sort click (only on sortable th – not .th-focus)
  DRAWER_BODY.querySelectorAll("thead th[data-col]").forEach(th => {
    th.addEventListener("click", () => {
      const col = th.dataset.col;
      if (sortCol === col) sortAsc = !sortAsc;
      else { sortCol = col; sortAsc = true; }
      expandedRow = null;
      renderTable();
    });
  });

  // row expand/collapse (click anywhere on the row except the focus button)
  DRAWER_BODY.querySelectorAll("tbody tr[data-idx]").forEach(tr => {
    tr.addEventListener("click", e => {
      if (e.target.closest(".btn-focus-node")) return;  // handled separately
      const idx = parseInt(tr.dataset.idx, 10);
      expandedRow = expandedRow === idx ? null : idx;
      renderTable();
    });
  });

  // focus button — pan+zoom the graph to the node then close the drawer
  DRAWER_BODY.querySelectorAll(".btn-focus-node").forEach(btn => {
    btn.addEventListener("click", e => {
      e.stopPropagation();
      focusNode(btn.dataset.nodeid);
      closeDrawer();
    });
  });
}

// update tab count badges after data loads
function updateTabCounts() {
  TAB_BTNS.forEach(btn => {
    const tab   = btn.dataset.tab;
    const count = (DATA[tab] || []).length;
    let badge = btn.querySelector(".tab-count");
    if (!badge) {
      badge = document.createElement("span");
      badge.className = "tab-count";
      btn.appendChild(badge);
    }
    badge.textContent = count;
  });
}

// ── data loading ──────────────────────────────────────────────────────────────

async function loadAll() {
  setStatus("Fetching data…");
  try {
    // load graph + all raw lists in parallel
    const [graphRes, agentsRes, toolsRes, toolkitsRes, connectionsRes] = await Promise.all([
      fetch(`${API_BASE}/api/graph`),
      fetch(`${API_BASE}/api/agents`),
      fetch(`${API_BASE}/api/tools`),
      fetch(`${API_BASE}/api/toolkits`),
      fetch(`${API_BASE}/api/connections`),
    ]);

    if (!graphRes.ok) throw new Error(`HTTP ${graphRes.status}`);

    const [graph, agents, tools, toolkits, connections] = await Promise.all([
      graphRes.json(), agentsRes.json(), toolsRes.json(),
      toolkitsRes.json(), connectionsRes.json(),
    ]);

    DATA.agents      = agents      || [];
    DATA.tools       = tools       || [];
    DATA.toolkits    = toolkits    || [];
    DATA.connections = connections || [];

    renderGraph(graph);
    updateTabCounts();
    // refresh table if drawer is open
    if (DRAWER.classList.contains("open")) renderTable();

  } catch (err) {
    setStatus(`Error: ${err.message}`, true);
    console.error("loadAll failed:", err);
  }
}

// ── window resize ─────────────────────────────────────────────────────────────

window.addEventListener("resize", () => loadAll());

// ── bootstrap ─────────────────────────────────────────────────────────────────

document.getElementById("btn-refresh").addEventListener("click", loadAll);

loadAll();
