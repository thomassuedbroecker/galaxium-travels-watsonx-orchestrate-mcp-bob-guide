# 9. Configure IBM Bob For This Repository

This repository already contains the Bob-related project files needed for the
local workflow.

The active Bob configuration is stored in:

- `.bob`
- `.bobrules`
- `.bobignore`
- `AGENTS.md`

The repository also contains one Bob support folder:

- `bob-modes-exports/`

## 9.1 Current Bob-Related Structure

The current Bob-related files in this repository are:

```text
.bob/
├── custom_modes.yaml
├── mcp.json
└── skills/
    └── galaxium_travels_watsonx_orchestrate_customization_developer.md

.bobrules/
├── rules-code/
│   └── coding-style.md
└── rules-galaxium-travels-developer-mode-2026-03-26/
    ├── coding-style.md
    └── watsonx-orchestrate-configurations.md

.bobignore
AGENTS.md

bob-modes-exports/
└── README.md
```

## 9.2 Active Bob Configuration Files

For day-to-day Bob usage in this repository, the active files are:

- `.bob/mcp.json`
- `.bob/custom_modes.yaml`
- `.bob/skills/...`
- `.bobrules/rules-code/...`
- `.bobrules/rules-galaxium-travels-developer-mode-2026-03-26/...`
- `.bobignore`
- `AGENTS.md`

The `bob-modes-exports/` folder is only support material in the repository. It
is not part of the main active Bob configuration used by the project-local Bob
setup.

## 9.3 The `.bob/mcp.json` File

The file `.bob/mcp.json` currently configures four MCP server entries:

- `watsonx-orchestrate-documentation-mcp`
- `watsonx-orchestrate-adk`
- `watsonx-orchestrate-local-mcp`
- `booking-mcp`

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
        "ibm-watsonx-orchestrate==2.2.0",
        "ibm-watsonx-orchestrate-mcp-server==2.2.0"
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
    }
  }
}
```

### What The Four Entries Do

- `watsonx-orchestrate-documentation-mcp` connects Bob to the public
  `watsonx Orchestrate` documentation MCP endpoint.
- `watsonx-orchestrate-adk` starts the local ADK-based MCP integration through
  `uvx`.
- `watsonx-orchestrate-local-mcp` connects Bob to the locally reachable
  `watsonx Orchestrate` MCP endpoint on port `8080`.
- `booking-mcp` connects Bob to the Galaxium Travels MCP server on port `8084`
  and sends a Basic Auth header.

### Local Values You May Need To Change

The current file uses `192.168.2.53` as the local host IP for:

- `watsonx-orchestrate-local-mcp`
- `booking-mcp`

If your local IP is different, update both URLs.

On macOS you can inspect the Wi-Fi IP with:

```sh
ipconfig getifaddr en0
```

## 9.4 The `.bob/custom_modes.yaml` File

The file `.bob/custom_modes.yaml` defines one custom Bob mode:

- slug: `galaxium-travels-developer-mode-2026-03-26`
- name: `Galaxium Travels Developer`

The current mode is intended for:

- Python development
- `watsonx Orchestrate` integration
- MCP server work
- container-based local development
- authentication, debugging, and API integration tasks

The enabled Bob groups are:

- `read`
- `edit`
- `browser`
- `command`
- `mcp`
- `modes`

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

## 9.5 The Skill In `.bob/skills`

The folder `.bob/skills` currently contains one skill file:

- `galaxium_travels_watsonx_orchestrate_customization_developer.md`

This skill supports development for the `watsonx Orchestrate` Developer Edition
customization in this repository.

The current skill focuses on:

- Python-based implementation
- MCP integration patterns
- clean customization structure
- separation between configuration and executable code
- local and container-based workflows

The skill currently points at this intended customization target:

```text
watsonx-orchestrate-adk/customization
```

It also recommends this layout:

```text
customization/
├── configurations/
│   ├── agents/
│   ├── tools/
│   ├── connections/
│   └── environments/
├── implementations/
│   ├── agents/
│   ├── tools/
│   ├── integrations/
│   └── utils/
```

## 9.6 The `.bobrules` Folder

The `.bobrules` folder currently contains two rule areas:

- `.bobrules/rules-code/`
- `.bobrules/rules-galaxium-travels-developer-mode-2026-03-26/`

The two `coding-style.md` files currently define the same coding standards for:

- consistency in formatting, naming, and structure
- readable code
- descriptive names for variables, functions, and classes
- consistent indentation and whitespace
- short lines
- small and focused functions
- comments that explain why, not only what

The file
`.bobrules/rules-galaxium-travels-developer-mode-2026-03-26/watsonx-orchestrate-configurations.md`
currently contains one short rule:

> Any configuration must fit to the used watsonx Orchestrate ADK!

## 9.7 The `.bobignore` File

The file `.bobignore` exists in the repository, but it is currently empty.

## 9.8 The `AGENTS.md` File

The file `AGENTS.md` adds repository-level team standards for agent-based work.

The current file states these main rules:

- minimize context usage wherever possible
- provide an answer only when the accuracy of the sources can be verified, otherwise state `Insufficient information.`
- use only approved libraries, especially open-source libraries or libraries provided by IBM
- keep code documentation to the minimum necessary

These instructions complement the `.bob` and `.bobrules` files.

## 9.9 Export Support Files

The repository also contains Bob-related support material outside the main
active configuration.

### `bob-modes-exports/`

This folder currently contains:

- `README.md`

At the moment this folder is only a placeholder location for Bob mode exports.
No exported mode YAML file is currently checked into the repository.

## 9.10 Basic Auth Header Used In The Repository

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

## 9.11 Summary

The Bob-related repository content is currently organized like this:

- `.bob/` contains the active MCP, mode, and skill configuration
- `.bobrules/` contains the active Bob rules
- `.bobignore` exists and is currently empty
- `AGENTS.md` contains repository-level agent guidance
- `bob-modes-exports/` is currently a placeholder folder for future export files

### [Home](./README.md)
