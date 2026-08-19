# IBM Bob - Watsonx Orchestrate (skill)

A Bob skill for building, testing, debugging, and publishing
**IBM watsonx Orchestrate** agents, tools, flows, MCP toolkits, connections, models,
and knowledge bases with the **Agent Development Kit (ADK)** and the `orchestrate` CLI.

Covers the full lifecycle: connect (SaaS / on-prem / local Developer Edition) → scaffold
→ author tools/flows/agents → import (dependency-ordered) → single/multi-turn chat test
→ export/reimport → observability → deploy. Also covers multi-agent orchestration,
AgentOps evaluations, chat-with-docs, embedded web chat, and the runtime REST API for
embedding a deployed agent in your own app.

## Built & verified for

- **ADK: `ibm-watsonx-orchestrate` 2.15.0** (Python 3.11–3.14)
- **Live-verified:** 2026-08-18 against a real IBM Cloud SaaS instance (us-south).
  Controls were created, enforced, exported, re-imported, updated and removed; a
  two-knowledge-base agent was built, deployed and shown to query both KBs in a single
  turn; voice configs, a document-processing flow and a custom API-key header were
  exercised — including one 2.15.0 feature (`connections configure --name`) found to be
  **broken on the SaaS backend**. Evidence in the repo `test/house_clinic/` folder.
- **2.15.0 coverage:** `orchestrate controls` (policy artifacts bound to agents/tools/
  models at execution hooks — **proved to enforce at runtime**), multiple knowledge bases
  per agent, `welcome_content.is_user_barge_in_disabled`, voice idle-handler fields,
  `connections configure --name`, Deepgram Flux STT.
- **2.14.0 coverage:** `language=` on document-processing nodes, the 30-class classifier
  cap, Google TTS and Deepgram `normalize_volume`, `on_flow_abort` / `on_flow_delete`,
  optional KB `index_config.url`, `redhat-ai` and `msftstudio` providers, and observability
  export for agents running outside wxO (OpenTelemetry / Observability SDK).
- **Three release-note claims are corrected here** because they don't match the shipped
  build: the welcome-message cap is still **100** characters (not 1000), the model provider
  is **`redhat-ai`** (not `red_hat_ai`), and the external-agent provider is **`msftstudio`**
  (not `microsoft_copilot_studio`).
- **2.13.0 coverage (retained):** agent **skills** (`orchestrate skills`, agent `skills:`
  field), `react_core` default style (default/react/planner deprecated), premier models
  (GPT-5.4), traces observations + `--last`, flow `suppress_agent_summarization` /
  `page_range`.

> The ADK moves fast - when a flag or field is uncertain, prefer
> `orchestrate <group> --help`. Re-run the `test/` project to re-verify after an ADK bump.

## Contents

- `SKILL.md` — the skill (lifecycle, schemas, constraints, debugging, publishing).
- `references/` — load-on-demand deep dives: CLI reference, agent/tool/flow schemas,
  connections/models/KB, MCP toolkits, runtime-API embedding, testing & debugging,
  AgentOps evaluations, plus `setup-venv.sh` and `wxo-chat.sh` helper scripts.
