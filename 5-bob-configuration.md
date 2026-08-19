# 5. Configure IBM Bob For This Repository

This repository already contains the Bob-related project files needed for the
local workflow.

The active Bob configuration is stored in:

- `.bob`
- `.bobrules`
- `.bobignore`
- `AGENTS.md`

The repository also contains one Bob support folder:

- `bob-modes-exports/`

## 5.1 Current Bob-Related Structure

The current Bob-related files in this repository are:

```text
.bob/
├── custom_modes.yaml
├── mcp.json
└── skills
    └── watsonx-orchestrate
        ├── README.md
        ├── SKILL.md
        └── references
            ├── agentops-evaluations.md
            ├── agents-tools-schemas.md
            ├── cli-reference.md
            ├── connections-models-kb.md
            ├── mcp-toolkits.md
            ├── runtime-api-embedding.md
            ├── setup-venv.sh
            ├── testing-debugging.md
            └── wxo-chat.sh

.bobrules/
├── rules-code/
│   └── coding-style.md
└── rules-galaxium-travels-developer-mode-2026-07-02/
    ├── coding-style.md
    └── watsonx-orchestrate-configurations.md

.bobignore
AGENTS.md

bob-modes-exports/
└── README.md
```

## 5.2 Active Bob Configuration Files

For day-to-day Bob usage in this repository, the active files are:

- `.bob/mcp.json`
- `.bob/custom_modes.yaml`
- `.bob/skills/...`
- `.bobrules/rules-code/...`
- `.bobrules/rules-galaxium-travels-developer-mode-2026-07-02/...`
- `.bobignore`
- `AGENTS.md`

The `bob-modes-exports/` folder is only support material in the repository. It
is not part of the main active Bob configuration used by the project-local Bob
setup.

## 5.3 The `.bob/mcp.json` File

The file `.bob/mcp.json` currently configures five MCP server entries:

- `watsonx-orchestrate-documentation-mcp`
- `watsonx-orchestrate-adk`
- `watsonx-orchestrate-local-mcp`
- `booking-mcp`
- `bob-marketplace`

The current file content is:

```json
{
  "mcpServers": {
    "watsonx-orchestrate-documentation-mcp": {
      "type": "streamable-http",
      "url": "https://developer.watson-orchestrate.ibm.com/mcp"
    },
    "watsonx-orchestrate-adk": {
      "command": "uvx",
      "args": [
        "--with",
        "ibm-watsonx-orchestrate",
        "ibm-watsonx-orchestrate-mcp-server"
      ],
      "env": {
        "WXO_MCP_WORKING_DIRECTORY": ".",
        "WXO_MCP_DEBUG": ""
      },
      "timeout": 300
    },
    "watsonx-orchestrate-local-mcp": {
      "type": "streamable-http",
      "url": "http://192.168.2.53:8080/mcp"
    },
    "booking-mcp": {
      "headers": {
        "Authorization": "Basic ZGVtby1iYXNpYy11c2VyOmRlbW8tYmFzaWMtcGFzc3dvcmQ=",
        "Accept": "application/json"
      },
      "type": "streamable-http",
      "url": "http://192.168.2.53:8084/mcp"
    },
    "bob-marketplace": {
      "type": "streamable-http",
      "url": "http://127.0.0.1:51877/mcp",
      "headers": {
        "Bob-Marketplace-Token": "bob-marketplace-local"
      },
      "disabled": false,
      "alwaysAllow": [
        "search_assets",
        "get_asset",
        "list_installed",
        "list_favorites",
        "suggest_assets",
        "list_updates"
      ]
    }
  }
}
```

### What The Five Entries Do

- `watsonx-orchestrate-documentation-mcp` connects Bob to the public
  `watsonx Orchestrate` documentation MCP endpoint.
- `watsonx-orchestrate-adk` starts the local ADK-based MCP integration through
  `uvx`.
- `watsonx-orchestrate-local-mcp` connects Bob to the locally reachable
  `watsonx Orchestrate` MCP endpoint on port `8080`.
- `booking-mcp` connects Bob to the Galaxium Travels MCP server on port `8084`
  and sends a Basic Auth header.
- `bob-marketplace` connects Bob to the local Bob Marketplace server for
  searching, installing, and listing assets.

### Local Values You May Need To Change

The current file uses `192.168.2.53` as the local host IP for:

- `watsonx-orchestrate-local-mcp`
- `booking-mcp`

If your local IP is different, update both URLs.

On macOS you can inspect the Wi-Fi IP with:

```sh
ipconfig getifaddr en0
```

## 5.4 The `.bob/custom_modes.yaml` File

The file `.bob/custom_modes.yaml` defines one custom Bob mode:

- slug: `galaxium-travels-developer-mode-2026-07-02`
- name: `Galaxium Travels Developer`

The current mode is intended for:

- Python development
- `watsonx Orchestrate` integration
- MCP server work
- container-based local development
- authentication, debugging, and API integration tasks

The enabled Bob groups are ([details in the IBM Bob documentation](https://bob.ibm.com/docs/ide/configuration/custom-modes)):

- `read`
- `edit`
- `execute`
- `mcp`
- `skill`
- `workflow`
- `todo`
- `subtask`
- `subagent`

The current custom instructions tell Bob to:

- use Python for implementation examples and code changes
- prefer clear, maintainable, production-oriented solutions
- consider the existing project structure before proposing changes
- keep compatibility with container-based development and local execution workflows
- consider MCP server design, tool definitions, authentication flow, and `watsonx Orchestrate` integration when relevant
- favor simple, reproducible solutions over unnecessary complexity
- consider configuration, testing, logging, and error handling when useful
- align recommendations with real development tasks in the Galaxium Travels repository
- use the `Galaxium Travels watsonx Orchestrate Customization Developer` skill when relevant

## 5.5 The Skills In `.bob/skills`

The folder `.bob/skills` currently contains three skills:

### `watsonx-orchestrate`

Location: `.bob/skills/watsonx-orchestrate/`

- `SKILL.md` — the main skill definition activated when watsonx Orchestrate
  topics are relevant
- `README.md` — additional background material

The `references/` sub-folder contains supporting documents used by the skill:

| File | Content |
|---|---|
| `agentops-evaluations.md` | Agent evaluation patterns |
| `agents-tools-schemas.md` | Agent and tool YAML schemas |
| `cli-reference.md` | `orchestrate` CLI reference |
| `connections-models-kb.md` | Connections, models, and knowledge base guide |
| `mcp-toolkits.md` | MCP toolkit integration |
| `runtime-api-embedding.md` | Runtime REST API and embedding |
| `setup-venv.sh` | Virtual environment setup helper |
| `testing-debugging.md` | Testing and debugging guidance |
| `wxo-chat.sh` | Chat startup helper script |

The skill covers: building, importing, testing, debugging, and publishing IBM
watsonx Orchestrate agents, tools, flows, toolkits (MCP), connections, models,
and knowledge bases using the ADK and the `orchestrate` CLI.

### `wxo-log-inspector`

Location: `.bob/skills/wxo-log-inspector/`

- `SKILL.md` — the skill definition for the server log inspection pipeline

Used in guide `6` to run the structured log analysis via `bob run`. The skill
provides Bob with instructions for interpreting captured container logs and
producing the `BOB_ANALYSIS_REPORT.md`.

### `wxo-agent-analytics`

Location: `.bob/skills/wxo-agent-analytics/`

- `SKILL.md` — the skill definition for Langfuse trace analysis

Used in guide `7` to analyse single-run and session-window Langfuse traces via
`bob run`. The skill guides Bob through evaluating agent trace data exported by
`wxo_bob_agent_analytics.sh` and `wxo_bob_session_analytics.sh`.

## 5.6 The `.bobrules` Folder

The `.bobrules` folder currently contains two rule areas:

- `.bobrules/rules-code/`
- `.bobrules/rules-galaxium-travels-developer-mode-2026-07-02/`

The two `coding-style.md` files currently define the same coding standards for:

- consistency in formatting, naming, and structure
- readable code
- descriptive names for variables, functions, and classes
- consistent indentation and whitespace
- short lines
- small and focused functions
- comments that explain why, not only what

The file
`.bobrules/rules-galaxium-travels-developer-mode-2026-07-02/watsonx-orchestrate-configurations.md`
currently contains two rules:

> Any configuration must fit to the used watsonx Orchestrate ADK!

> For watsonx Orchestrate ADK version 2.12.0 you must use
> `llm: watsonx/meta-llama/llama-3-3-70b-instruct` for the agent
> configuration.

## 5.7 The `.bobignore` File

The file `.bobignore` exists in the repository, but it is currently empty.

## 5.8 The `AGENTS.md` File

The file `AGENTS.md` adds repository-level team standards for agent-based work.

The current file states these main rules:

- minimize context usage wherever possible
- provide an answer only when the accuracy of the sources can be verified, otherwise state `Insufficient information.`
- use only approved libraries, especially open-source libraries or libraries provided by IBM
- keep code documentation to the minimum necessary

These instructions complement the `.bob` and `.bobrules` files.

## 5.9 Export Support Files

The repository also contains Bob-related support material outside the main
active configuration.

### `bob-modes-exports/`

This folder currently contains:

- `README.md`

At the moment this folder is only a placeholder location for Bob mode exports.
No exported mode YAML file is currently checked into the repository.

## 5.10 Basic Auth Header Used In The Repository

The current `booking-mcp` entry uses this Basic Auth value:

```text
Basic ZGVtby1iYXNpYy11c2VyOmRlbW8tYmFzaWMtcGFzc3dvcmQ=
```

That value corresponds to the demo credentials used in this repository:

- username: `demo-basic-user`
- password: `demo-basic-password`

If you need to rebuild the token manually:

```sh
BASIC_AUTH_USERNAME=demo-basic-user
BASIC_AUTH_PASSWORD=demo-basic-password
BASIC_TOKEN="$(printf '%s' "${BASIC_AUTH_USERNAME}:${BASIC_AUTH_PASSWORD}" | base64 | tr -d '\r\n')"
echo "${BASIC_TOKEN}"
```

## 5.11 Summary

The Bob-related repository content is currently organized like this:

- `.bob/` contains the active MCP, mode, and skill configuration
- `.bobrules/` contains the active Bob rules
- `.bobignore` exists and is currently empty
- `AGENTS.md` contains repository-level agent guidance
- `bob-modes-exports/` is currently a placeholder folder for future export files

### [Home](./README.md)
