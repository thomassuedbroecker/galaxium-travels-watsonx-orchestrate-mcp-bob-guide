# Third-Party Notices

This repository is licensed under the MIT License. See [LICENSE](LICENSE).

The MIT License applies to the repository content authored for this guide. It
does not grant rights to IBM products, external services, third-party packages,
third-party tools, trademarks, screenshots, videos, external repositories, or
documentation referenced from this repository. Those materials remain governed
by their own licenses, service terms, or usage permissions.

This notice is a best-effort inventory for the guide content and local workflow
references. It is not legal advice.

## IBM Products, Services, And Documentation

This guide references IBM Bob, IBM watsonx Orchestrate, watsonx Orchestrate
Developer Edition, watsonx.ai, IBM Cloud, and related IBM documentation.

Use of IBM products and services may require valid IBM entitlements,
credentials, subscriptions, or other authorization. The repository license does
not grant any IBM product license or service entitlement.

Relevant references:

- IBM watsonx Orchestrate ADK documentation:
  <https://developer.watson-orchestrate.ibm.com/>
- IBM watsonx Orchestrate Developer Edition installation documentation:
  <https://developer.watson-orchestrate.ibm.com/developer_edition/wxOde_setup>
- IBM watsonx Orchestrate ADK license information:
  <https://developer.watson-orchestrate.ibm.com/license/li_en>
- IBM International Program License Agreement reference:
  <https://developer.watson-orchestrate.ibm.com/license/la_en>

IBM, watsonx, watsonx Orchestrate, and related marks are trademarks or
registered trademarks of IBM or its affiliates. This repository is an
independent guide and does not imply IBM endorsement.

## Python Packages Referenced By The Workflow

The repository does not ship a root Python package manifest. It documents local
installation commands and Bob MCP configuration that reference these pinned
Python packages:

| Package | Version | License recorded by this repository | Where referenced |
| --- | ---: | --- | --- |
| `ibm-watsonx-orchestrate` | `2.12.0` | MIT | `3-watsonx-orchestrate-adk-setup.md`, `.bob/mcp.json` |
| `ibm-watsonx-orchestrate-mcp-server` | `2.12.0` | MIT | `3-watsonx-orchestrate-adk-setup.md`, `.bob/mcp.json` |

The packages and their transitive dependencies are not vendored in this
repository. Review the package metadata and dependency tree resolved in your
own environment before redistributing any generated environment, container
image, or packaged artifact.

## CLI Tools And Runtime Prerequisites

The guide references the following tools. They are not bundled in this
repository and remain subject to their own license or service terms:

| Tool or component | Notes |
| --- | --- |
| `git` | Used to clone related repositories. |
| `curl` | Used for manual HTTP verification flows. |
| `jq` | Used for command-line JSON inspection. |
| `npx` / Node.js tooling | Used for optional MCP Inspector commands. |
| `uvx` | Used by `.bob/mcp.json` to start the local ADK-based MCP integration. |
| Docker Desktop | Optional container runtime; Docker Desktop is governed by Docker's subscription terms. |
| Rancher Desktop or other container runtimes | Optional alternatives governed by their own licenses and terms. |
| MCP Inspector | Optional Model Context Protocol inspection tooling referenced by the guide. |

## External Repositories

The guide references these external repositories. Their content is not part of
this repository unless separately cloned by the user, and each repository keeps
its own license and notices:

- Galaxium Travels infrastructure:
  <https://github.com/thomassuedbroecker/galaxium-travels-infrastructure-tsuedbro>
- Older integration repository:
  <https://github.com/thomassuedbroecker/galaxium-travels-mcp-compose-watsonx-orchestrate>

## Media And Diagram Assets

The repository includes:

- `images/youtube-01.jpg`, used as the preview image for the related YouTube
  video linked from `README.md`.
- `architecture/galaxim-travel-infrastructure.drawio`, an editable Draw.io
  architecture diagram.

The Draw.io diagram uses Draw.io library references such as built-in clip art,
Azure-style browser icons, active-directory-style security icons, and network
icons. These library assets and icon references remain subject to the licensing
or terms that apply to Draw.io and the relevant icon libraries.

The YouTube preview image is included only to identify and link to the related
video. Do not assume that this image can be reused independently of the video,
YouTube terms, or the rights holder's permission.

## Generated Or AI-Assisted Content

This repository contains Bob configuration, prompt text, and agent-oriented
workflow guidance. If future changes add AI-generated source code, generated
configuration, copied documentation excerpts, or generated media, record the
source, tool, review status, and applicable license or usage terms here.

## Maintenance

Update this file when:

- a new package, CLI tool, service, image, screenshot, diagram source, or
  external repository is added;
- referenced package versions change;
- generated artifacts are committed;
- this repository starts shipping an installable package, container image, or
  bundled runtime environment.
