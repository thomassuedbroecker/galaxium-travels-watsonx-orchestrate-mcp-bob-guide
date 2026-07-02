# Dependency And License Transparency

This document maps the dependencies, tools, and runtime prerequisites referenced
by this guide. It is scoped to the repository's documented workflow; it is not a
complete SBOM for any local virtual environment, container runtime, IBM product
installation, or generated deployment artifact.

Review date: `2026-05-29`
Last updated: `2026-06-02` (added `watsonx_orchestrate_custom_explorer` application dependencies)

Repository license: MIT. See [LICENSE](LICENSE).

Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Scope And Assumptions

- This repository is documentation plus helper shell scripts. It does not ship a
  root `pyproject.toml`, `requirements.txt`, `package.json`, lockfile, or
  container image.
- The IBM Python packages below are installed by user-run commands or launched
  through Bob MCP configuration. They are not vendored in this repository.
- License entries are based on upstream project/package metadata and public
  documentation. Transitive dependencies are not enumerated here.
- IBM product access remains governed by IBM entitlements and product terms,
  even where an IBM-published Python package lists an open-source license.

## License Mapping

| Component | Version or pin used here | License or terms recorded | Source used for mapping | Repository scope | Follow-up for redistribution |
| --- | --- | --- | --- | --- | --- |
| `ibm-watsonx-orchestrate` | `2.12.0` | MIT License in PyPI metadata | <https://pypi.org/project/ibm-watsonx-orchestrate/2.12.0/> | Installed by setup guide and referenced from `.bob/mcp.json` | Generate a resolved dependency report before distributing any environment or image. |
| `ibm-watsonx-orchestrate-mcp-server` | `2.12.0` | MIT License in PyPI metadata | <https://pypi.org/project/ibm-watsonx-orchestrate-mcp-server/> | Installed by setup guide and referenced from `.bob/mcp.json` | Generate a resolved dependency report before distributing any environment or image. |
| IBM watsonx Orchestrate Developer Edition | Not pinned as a package in this repo | IBM product entitlement and license terms apply | <https://developer.watson-orchestrate.ibm.com/developer_edition/wxOde_setup>, <https://developer.watson-orchestrate.ibm.com/license/li_en> | Required runtime/service context for the documented workflow | Confirm user entitlement and IBM terms before use in any organization or delivery context. |
| `npx` / npm CLI | Not pinned | npm CLI: Artistic-2.0; npm registry/service terms also apply when fetching packages | <https://github.com/npm/cli>, <https://raw.githubusercontent.com/npm/cli/latest/LICENSE> | Used for optional MCP Inspector execution | Pin Node.js/npm versions for reproducible audit evidence if this becomes an automated workflow. |
| `uvx` / `uv` | Not pinned | Apache-2.0 OR MIT, at user's option | <https://github.com/astral-sh/uv> | Used by `.bob/mcp.json` to launch Python tools in an ephemeral environment | Pin `uv` version and capture resolved Python dependencies for release evidence. |
| Docker Desktop | Not pinned | Docker Subscription Service Agreement; open-source component notices also apply | <https://docs.docker.com/subscription/desktop-license/> | Optional local container runtime | Confirm whether the user's organization needs a paid Docker subscription. |
| Rancher Desktop | Not pinned | Apache-2.0 | <https://github.com/rancher-sandbox/rancher-desktop> | Optional local container runtime alternative | Capture runtime version if used for support or audit evidence. |
| `curl` | Not pinned | curl license | <https://curl.se/docs/copyright.html> | Used in manual HTTP verification commands | Normally system-provided; record version for reproducible test evidence. |
| `jq` | Not pinned | MIT for `jq`; documentation under CC BY 3.0; includes decNumber under ICU License | <https://github.com/jqlang/jq> | Used in manual JSON inspection commands | Normally system-provided; record version for reproducible test evidence. |
| **`flask`** (watsonx_orchestrate_custom_explorer) | `3.0.0` | BSD-3-Clause | <https://pypi.org/project/Flask/3.0.0/>, <https://github.com/pallets/flask/blob/main/LICENSE.txt> | Backend web framework for the Custom Explorer app | BSD-3-Clause is permissive; no redistribution constraints beyond attribution. |
| **`flask-cors`** (watsonx_orchestrate_custom_explorer) | `4.0.0` | MIT | <https://pypi.org/project/Flask-Cors/4.0.0/>, <https://github.com/corydolphin/flask-cors/blob/main/LICENSE> | CORS middleware for the Flask backend | MIT is permissive. |
| **`python-dotenv`** (watsonx_orchestrate_custom_explorer) | `>=1.1.0` (required by fastmcp in the SDK venv) | BSD-3-Clause | <https://pypi.org/project/python-dotenv/>, <https://github.com/theskumar/python-dotenv/blob/main/LICENSE> | Loads `.env` file into environment at startup | BSD-3-Clause is permissive. |
| **D3.js v7** (watsonx_orchestrate_custom_explorer frontend) | `7.9.0` | ISC (functionally equivalent to MIT) | <https://github.com/d3/d3/blob/main/LICENSE>, <https://cdn.jsdelivr.net/npm/d3@7.9.0/> | Force-directed graph rendering in the browser; loaded from jsDelivr CDN | ISC is permissive. The jsDelivr CDN is open-source (<https://github.com/jsdelivr/jsdelivr>); no tracking or proprietary analytics included. |

## IBM Package And Product Boundary

The Python packages `ibm-watsonx-orchestrate==2.12.0` and
`ibm-watsonx-orchestrate-mcp-server==2.12.0` are listed as MIT-licensed packages
in PyPI metadata. That package license does not replace the IBM product
entitlement requirements for watsonx Orchestrate Developer Edition, watsonx.ai,
IBM Cloud services, or other IBM services used by the workflow.

The setup guide requires these credentials:

- `WO_ENTITLEMENT_KEY`
- `WATSONX_APIKEY`
- `WATSONX_SPACE_ID`

Treat those credentials and related services as IBM-governed product/service
usage, not as open-source dependencies of this repository.

## Transitive Dependency Gap

This repository does not currently include a lockfile or generated dependency
inventory. The following are intentionally not covered by this document:

- transitive Python packages installed by the IBM packages;
- packages executed through `npx`, including MCP Inspector dependencies;
- packages resolved by `uvx` at runtime;
- operating-system packages supplied by the user's machine;
- Docker Desktop or Rancher Desktop bundled components;
- IBM Developer Edition containers, service images, or separately licensed code.

Before distributing a packaged environment, container image, course image, or
customer deliverable derived from this guide, generate a fresh dependency and
license report from the exact environment being delivered.

## Suggested Audit Commands

Use commands like these in the local environment used for a release or handover:

```sh
python -m pip install pip-licenses
python -m piplicenses --format=markdown --with-system --with-urls
npm view @modelcontextprotocol/inspector license version dependencies
uvx --version
npx --version
curl --version
jq --version
```

For containerized or IBM Developer Edition artifacts, use the scanning and
notices workflow required by the target organization and IBM entitlement terms.

## Maintenance Rule

Update this file when:

- package versions change;
- new CLI tools or services are added;
- this repository starts shipping a lockfile, container image, generated
  environment, or installable package;
- IBM product terms or entitlement assumptions change;
- a release requires enterprise procurement, customer delivery, or audit
  evidence.
