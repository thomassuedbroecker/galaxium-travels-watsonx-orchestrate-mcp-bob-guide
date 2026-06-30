"""
app.py – Flask entry-point for the watsonx Orchestrate Custom Explorer.
"""
import os
import logging
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, jsonify, send_from_directory, abort, make_response
from flask_cors import CORS

# ── bootstrap ──────────────────────────────────────────────────────────────
_ROOT = Path(__file__).parent.parent          # .../watsonx_orchestrate_custom_explorer/
load_dotenv(dotenv_path=_ROOT / ".env", override=False)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
logger = logging.getLogger(__name__)

# ── import after env is loaded so api.py picks up WXO_MCP_BASE_URL ─────────
from api import fetch_agents, fetch_tools, fetch_connections, fetch_toolkits, mcp_url  # noqa: E402
from graph import build_graph                                                           # noqa: E402

_PUBLIC = _ROOT / "public"

app = Flask(__name__, static_folder=str(_PUBLIC), static_url_path="")
app.config["SEND_FILE_MAX_AGE_DEFAULT"] = 0   # disable Flask static caching
CORS(app)


# ── static frontend ────────────────────────────────────────────────────────

def _no_cache(response):
    """Add no-cache headers to every static file response."""
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"]        = "no-cache"
    response.headers["Expires"]       = "0"
    return response


@app.route("/")
def index():
    return _no_cache(make_response(send_from_directory(_PUBLIC, "index.html")))


@app.route("/<path:filename>")
def static_files(filename: str):
    target = _PUBLIC / filename
    if not target.exists():
        abort(404)
    return _no_cache(make_response(send_from_directory(_PUBLIC, filename)))


# ── REST API ───────────────────────────────────────────────────────────────

@app.route("/api/agents")
def api_agents():
    return jsonify(fetch_agents())


@app.route("/api/tools")
def api_tools():
    return jsonify(fetch_tools())


@app.route("/api/connections")
def api_connections():
    return jsonify(fetch_connections())


@app.route("/api/toolkits")
def api_toolkits():
    return jsonify(fetch_toolkits())


@app.route("/api/graph")
def api_graph():
    agents      = fetch_agents()
    tools       = fetch_tools()
    connections = fetch_connections()
    toolkits    = fetch_toolkits()
    graph       = build_graph(agents, tools, connections, toolkits)
    return jsonify(graph)


@app.route("/api/health")
def api_health():
    import socket
    url = mcp_url()
    host = url.split("//")[-1].split(":")[0]
    port_str = url.split(":")[-1].split("/")[0]
    try:
        s = socket.create_connection((host, int(port_str)), timeout=2)
        s.close()
        mcp_reachable = True
    except OSError:
        mcp_reachable = False
    return jsonify({"status": "ok", "mcp_url": url, "mcp_reachable": mcp_reachable})


# ── main ───────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    port  = int(os.environ.get("EXPLORER_PORT", 5001))
    debug = os.environ.get("EXPLORER_DEBUG", "false").lower() == "true"
    logger.info("Starting Custom Explorer on port %d (debug=%s)", port, debug)
    app.run(host="0.0.0.0", port=port, debug=debug)
