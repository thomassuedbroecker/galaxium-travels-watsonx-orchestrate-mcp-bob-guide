# From Local Infrastructure to AI Booking Agent: Galaxium Travels with watsonx Orchestrate and IBM Bob

This repository is a step-by-step guide to building a local AI travel booking agent using **watsonx Orchestrate Developer Edition** and **IBM Bob**. It walks you through every step — from infrastructure setup to agent creation — using the Galaxium Travels example application.

## What You Will Build

A local environment where:

- `watsonx Orchestrate Developer Edition` runs inside a Lima VM on your laptop
- The Galaxium Travels MCP server runs locally with Basic Auth
- IBM Bob assists with configuration, log inspection, agent analytics, and agent creation

Here is what the finished agent looks like:

![Galaxium booking agent in watsonx Orchestrate](./images/watsonx_orchestrate_agent_02.jpg)

![Galaxium booking agent response](./images/watsonx_orchestrate_agent_01.jpg)

## Prerequisites

Before starting, you need:

- A container runtime supported by the watsonx Orchestrate ADK (Rancher Desktop with Lima VM is used in this guide)
- An IBM entitlement key (`WO_ENTITLEMENT_KEY`)
- A watsonx.ai API key and Space ID (`WATSONX_APIKEY`, `WATSONX_SPACE_ID`)
- An IBM Bob API key (`BOB_API_KEY`) — create one at **bob.ibm.com → Account → API Keys** (scope: Inference); needed for guides 6 and 7

## Guide Flow

Work through the guides in order. Each guide builds on the previous one.

| # | Guide | What you do |
|---|---|---|
| 1 | [Set Up The Galaxium Travels Infrastructure](./1-galaxium_setup.md) | Clone and start the Galaxium Travels backend with Basic Auth |
| 2 | [Manually Verify The Basic Auth MCP Server](./2-galaxium_manual_basic_auth_mcp_verification.md) | Confirm the MCP server responds correctly before connecting it to watsonx Orchestrate |
| 3 | [Set Up The watsonx Orchestrate ADK](./3-watsonx-orchestrate-adk-setup.md) | Install the ADK, start the Developer Edition server, import the hello-world agent |
| 4 | [Add The Basic Auth MCP Server To watsonx Orchestrate](./4-watsonx-orchestrate-adk-add-basic-auth-mcp.md) | Register the Galaxium MCP server as a toolkit in watsonx Orchestrate |
| 5 | [Configure IBM Bob For This Repository](./5-bob-configuration.md) | Set up Bob modes, skills, and MCP connections for this project |
| 6 | [Inspect The watsonx Orchestrate Server Logs](./6-watsonx-server-inspection.md) | Capture and analyse container logs using `wxo_bob_log_inspect.sh` and IBM Bob |
| 7 | [Inspect Agent Analytics With IBM Bob](./7-watsonx-agent-analytics.md) | Analyse Langfuse traces for single runs and session windows using `wxo_bob_agent_analytics.sh` |
| 8 | [Prompts For IBM Bob](./8-bob-prompts.md) | Use prepared prompts to ask Bob to build the Galaxium booking agent |
| 9 | [watsonx Orchestrate Custom Agent Explorer](./watsonx-orchestrate-mcp-server/watsonx_orchestrate_custom_explorer/README.md) | Explore agents, tools, and connections as an interactive force-directed diagram |

## Use This Repository As A Template

This repository is a **GitHub template**. To start your own copy:

1. Click **"Use this template"** at the top of the repository page on GitHub.
2. Choose a name and visibility for your new repository.
3. Clone your new repository:

```sh
git clone https://github.com/<your-username>/<your-repo-name>.git
cd <your-repo-name>
```

> **Contributing:** To contribute documentation or examples back to the template, clone this repository directly instead:
> ```sh
> git clone https://github.com/thomassuedbroecker/galaxium-travels-watsonx-orchestrate-mcp-bob-guide.git
> cd galaxium-travels-watsonx-orchestrate-mcp-bob-guide
> ```

## Repository Layout

```text
├── .bob/
│   ├── custom_modes.yaml           ← IBM Bob custom modes
│   ├── mcp.json                    ← MCP server configuration for Bob
│   └── skills/
│       ├── watsonx-orchestrate/    ← ADK skill (agent/tool/flow reference)
│       ├── wxo-log-inspector/      ← log-inspection skill (guide 6)
│       └── wxo-agent-analytics/    ← agent analytics skill (guide 7)
├── .bobignore
├── .bobrules/                      ← Bob project rules
├── AGENTS.md                       ← team standards for agent work
├── 1-galaxium_setup.md
├── 2-galaxium_manual_basic_auth_mcp_verification.md
├── 3-watsonx-orchestrate-adk-setup.md
├── 4-watsonx-orchestrate-adk-add-basic-auth-mcp.md
├── 5-bob-configuration.md
├── 6-watsonx-server-inspection.md
├── 7-watsonx-agent-analytics.md
├── 8-bob-prompts.md
├── architecture/                   ← Draw.io infrastructure diagram
├── images/                         ← screenshots and GIFs
├── infrastructure/                 ← clone the Galaxium Travels repo here
├── prompts/                        ← prepared Bob prompts
├── watsonx-orchestrate-adk/
│   ├── wxo_local_start.sh              ← start the Developer Edition server
│   ├── wxo_server_log_inspector.sh     ← parallel log capture from all containers
│   ├── wxo_server_log_analyze.sh       ← sessions overview + ANALYSIS_REPORT.md
│   ├── wxo_bob_log_inspect.sh          ← chains capture + analyse + bob run (guide 6)
│   ├── wxo_bob_agent_analytics.sh      ← single-run Langfuse trace analysis (guide 7)
│   ├── wxo_bob_session_analytics.sh    ← time-window session analysis (guide 7)
│   ├── agents/                         ← agent YAML files
│   ├── model-configs/                  ← watsonx.ai model configuration templates
│   └── .env_template                   ← copy to .env and fill in your credentials
└── watsonx-orchestrate-mcp-server/
    └── watsonx_orchestrate_custom_explorer/   ← Flask + D3.js agent explorer app
```

## IBM Bob In This Repository

IBM Bob is used throughout this guide for:

- **Log inspection (guide 6):** `wxo_bob_log_inspect.sh` captures container logs, runs the analyser, and pipes the summary to `bob run` for a structured health report saved as `BOB_ANALYSIS_REPORT.md`.
- **Agent analytics (guide 7):** `wxo_bob_agent_analytics.sh` fires a test run, exports the Langfuse trace, and asks Bob to analyse it. `wxo_bob_session_analytics.sh` does the same across a time window of past runs.
- **Agent builder (guide 8):** prepared prompts ask Bob to build the Galaxium booking agent end-to-end.
- **Explorer app:** Bob generated the `watsonx_orchestrate_custom_explorer` Flask + D3.js application from scratch using the watsonx Orchestrate MCP server.

![watsonx Orchestrate Custom Agent Explorer](./images/watsonx_orchestrate_custom_explorer_01.gif)

The Bob configuration files in this repository are:

| File / folder | Purpose |
|---|---|
| `.bob/` | MCP server config, custom modes, and skills |
| `.bobignore` | Files Bob should not read |
| `.bobrules/` | Project-level rules for Bob |
| `AGENTS.md` | Team standards Bob follows in every session |
| `prompts/` | Prepared prompt text for the booking agent task |
| `bob-modes-exports/` | Exported Bob mode definitions |

## Related Videos And Blog Posts

**Update video** — Bob 2.0 + watsonx Orchestrate 2.12.0:

`Build an AI Booking Agent with MCP — an update with IBM Bob 2.0 + watsonx Orchestrate 2.12.0`

[![Related YouTube video](./images/youtube-01.jpg)](https://youtu.be/Ut5aXGEA9kA?si=b4c9jdcNUNBvPQXO)

**Initial video** — Bob 1.0 + watsonx Orchestrate 2.2.0:

`How to Use IBM Bob, MCP, and watsonx Orchestrate to Generate an Agent?`

[![Related YouTube video](./images/youtube-01.jpg)](https://youtu.be/QRb2_ZVlynE?si=MG6RmWewAlmGkSjn)

**Initial blog post:** [Using IBM Bob, MCP, and watsonx Orchestrate to Generate an Agent](https://suedbroecker.net/2026/03/29/using-ibm-bob-mcp-and-watsonx-orchestrate-to-generate-an-agent/)

> **Note:** The initial video and blog post were created with **Bob 1.0** and **watsonx Orchestrate 2.2.0**. The specific configuration steps shown there may differ from this guide. The core concept — running a local watsonx Orchestrate environment and connecting a Basic Auth MCP server via IBM Bob — remains the same.

## Open-Source Dependencies

This repository is primarily documentation and helper shell scripts. It does not declare a root-level `pyproject.toml` or `package.json`.

**Python version:** `3.13`

**Main runtime libraries:**

| Library | Version | License | Where referenced |
|---|---|---|---|
| `ibm-watsonx-orchestrate` | `2.12.0` | MIT | `3-watsonx-orchestrate-adk-setup.md`, `.bob/mcp.json` |
| `ibm-watsonx-orchestrate-mcp-server` | `2.12.0` | MIT | `3-watsonx-orchestrate-adk-setup.md`, `.bob/mcp.json` |

**`watsonx_orchestrate_custom_explorer` application (generated with IBM Bob):**

| Library | Version | License | Where referenced |
|---|---|---|---|
| `flask` | `3.0.0` | BSD-3-Clause | `watsonx_orchestrate_custom_explorer/requirements.txt` |
| `flask-cors` | `4.0.0` | MIT | `watsonx_orchestrate_custom_explorer/requirements.txt` |
| `python-dotenv` | `>=1.1.0` | BSD-3-Clause | `watsonx_orchestrate_custom_explorer/requirements.txt` |
| `mcp` (SDK) | inherited from parent `.venv` | Apache-2.0 | `watsonx_orchestrate_custom_explorer/src/api.py` |
| `D3.js` | `7.9.0` | ISC | `watsonx_orchestrate_custom_explorer/public/index.html` |

**CLI tools:**

| Tool | Notes |
|---|---|
| `git` | Clone the infrastructure repository |
| `curl` | Manual verification flows |
| `jq` | Used by the log-inspection scripts (`brew install jq` on macOS) |
| `npx` | Needed only if you use MCP Inspector |
| `uvx` | Used by `.bob/mcp.json` to launch the local ADK MCP server |
| `bob` CLI | `npm install -g @ibm/bob-cli` — required for guides 6 and 7 |

**IBM service credentials (not open-source libraries):**

| Variable | Where to get it |
|---|---|
| `WO_ENTITLEMENT_KEY` | [IBM Container Software Library](https://myibm.ibm.com/products-services/containerlibrary) |
| `WATSONX_APIKEY` | IBM Cloud → watsonx.ai service credentials |
| `WATSONX_SPACE_ID` | IBM Cloud → watsonx.ai deployment space |
| `BOB_API_KEY` | bob.ibm.com → Account → API Keys (scope: Inference) |

For the full dependency and license mapping see [Dependency And License Transparency](DEPENDENCY_LICENSE_TRANSPARENCY.md).

## Related Repositories

- Galaxium Travels infrastructure: <https://github.com/thomassuedbroecker/galaxium-travels-infrastructure-tsuedbro>
- Older integration reference: <https://github.com/thomassuedbroecker/galaxium-travels-mcp-compose-watsonx-orchestrate>

## Useful References

- watsonx Orchestrate ADK documentation: <https://developer.watson-orchestrate.ibm.com/>
- Importing remote MCP toolkits: <https://developer.watson-orchestrate.ibm.com/tools/toolkits/remote_mcp_toolkits#using-streamable-http>
- MCP transport specification: <https://modelcontextprotocol.io/specification/2025-06-18/basic/transports>
