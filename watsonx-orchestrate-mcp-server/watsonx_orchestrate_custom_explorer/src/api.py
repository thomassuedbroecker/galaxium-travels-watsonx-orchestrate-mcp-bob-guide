"""
api.py – calls the ibm-watsonx-orchestrate-mcp-server via the MCP
Streamable-HTTP transport using the official 'mcp' Python client library.

The MCP server MUST be running before this Flask app can return data.
Start it with:
    cd watsonx-orchestrate-mcp-server
    bash wxo_mcp_local_start.sh

Environment variables (set in .env):
    WXO_MCP_BASE_URL   URL of the running MCP server  (default: http://127.0.0.1:8080)
"""
import asyncio
import logging
import os

logger = logging.getLogger(__name__)

_MCP_PATH = "/mcp"          # FastMCP Streamable-HTTP default path
_TIMEOUT  = 15              # seconds per tool call


# ── public interface ──────────────────────────────────────────────────────────

def fetch_agents()      -> list[dict]: return _call_tool("list_agents",      {})
def fetch_tools()       -> list[dict]: return _call_tool("list_tools",        {})
def fetch_connections() -> list[dict]: return _call_tool("list_connections",  {})
def fetch_toolkits()    -> list[dict]: return _call_tool("list_toolkits",     {})

def mcp_url() -> str:
    # Read at call-time so changes to WXO_MCP_BASE_URL in the environment
    # after module import (e.g. set by start.sh) are always picked up.
    base = os.environ.get("WXO_MCP_BASE_URL", "http://127.0.0.1:8080")
    return f"{base}{_MCP_PATH}"


# ── MCP client ────────────────────────────────────────────────────────────────

def _call_tool(tool_name: str, arguments: dict) -> list[dict]:
    """
    Open a fresh MCP Streamable-HTTP session, call one tool, return its
    result as list[dict].  Returns [] and logs a warning on any failure.
    """
    try:
        return asyncio.run(_async_call_tool(tool_name, arguments))
    except Exception as exc:
        logger.warning("MCP tool call '%s' failed: %s", tool_name, exc)
        return []


async def _async_call_tool(tool_name: str, arguments: dict) -> list[dict]:
    from mcp.client.streamable_http import streamablehttp_client
    from mcp import ClientSession

    url = mcp_url()
    async with streamablehttp_client(url, timeout=_TIMEOUT) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(tool_name, arguments)
            return _parse_content(result.content)


# ── result parsing ────────────────────────────────────────────────────────────

def _parse_content(content) -> list[dict]:
    """
    MCP tool results are a list of content blocks.  Each block with
    type='text' carries JSON produced by the ibm-watsonx-orchestrate SDK.
    Parse and flatten everything into list[dict].
    """
    import json

    if not content:
        return []

    out: list[dict] = []
    for block in content:
        # mcp library returns TextContent / EmbeddedResource objects
        text = getattr(block, "text", None)
        if text is None:
            if isinstance(block, dict):
                text = block.get("text")
        if not text:
            continue

        try:
            parsed = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            continue

        if isinstance(parsed, list):
            out.extend(_to_dict(item) for item in parsed)
        elif isinstance(parsed, dict):
            # agents returns {"native":[...], "external":[...], "assistant":[...]}
            # connections returns {"non_configured":[...], "draft":[...], "live":[...]}
            has_list_values = any(isinstance(v, list) for v in parsed.values())
            if has_list_values:
                for v in parsed.values():
                    if isinstance(v, list):
                        out.extend(_to_dict(item) for item in v)
            else:
                out.append(parsed)

    return out


def _to_dict(obj) -> dict:
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "model_dump"):      # Pydantic v2
        return obj.model_dump()
    if hasattr(obj, "dict"):            # Pydantic v1
        return obj.dict()
    if hasattr(obj, "__dict__"):
        return vars(obj)
    return {"value": str(obj)}
