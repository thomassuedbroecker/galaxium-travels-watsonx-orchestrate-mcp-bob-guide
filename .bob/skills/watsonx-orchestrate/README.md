# IBM Bob - Watsonx Orchestrate (skill)

Source: https://github.com/nheidloff/orchestrate-bob

A Bob skill for building, testing, debugging, and publishing
**IBM watsonx Orchestrate** agents, tools, flows, MCP toolkits, connections, models,
and knowledge bases with the **Agent Development Kit (ADK)** and the `orchestrate` CLI.

Covers the full lifecycle: connect (SaaS / on-prem / local Developer Edition) → scaffold
→ author tools/flows/agents → import (dependency-ordered) → single/multi-turn chat test
→ export/reimport → observability → deploy. Also covers multi-agent orchestration,
AgentOps evaluations, chat-with-docs, embedded web chat, and the runtime REST API for
embedding a deployed agent in your own app.

## Built & verified for

- **ADK: `ibm-watsonx-orchestrate` 2.12.0** (Python 3.11–3.14)
- **Live-verified:** 2026-06-29 against a real IBM Cloud SaaS instance (us-south),
  end-to-end (build → chat → orchestrate → evaluate → embed). 

> The ADK moves fast - when a flag or field is uncertain, prefer
> `orchestrate <group> --help`. Re-run the `test/` project to re-verify after an ADK bump.

## Contents

- `SKILL.md` — the skill (lifecycle, schemas, constraints, debugging, publishing).
- `references/` — load-on-demand deep dives: CLI reference, agent/tool/flow schemas,
  connections/models/KB, MCP toolkits, runtime-API embedding, testing & debugging,
  AgentOps evaluations, plus `setup-venv.sh` and `wxo-chat.sh` helper scripts.
