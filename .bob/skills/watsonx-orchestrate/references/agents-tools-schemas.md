# Agents, Tools & Flows — schemas and decorators

Grounded in the ADK source (`agent_builder/agents/types.py`,
`agent_builder/tools/python_tool.py`, `flow_builder`).

---

## 1. Agent YAML — `kind: native`

```yaml
spec_version: v1                 # REQUIRED
kind: native                     # REQUIRED
name: my_agent                   # REQUIRED — snake_case, no spaces
description: What this agent does and when to use it.   # REQUIRED (used for routing)
display_name: My Agent           # optional, UI label
instructions: |                  # the system prompt / behavior
  You are ... When the user ..., call <tool>. Be concise.
llm: watsonx/meta-llama/llama-3-3-70b-instruct   # defaults to tenant default if omitted
llm_config:                      # optional (2.11+) — per-agent decoding params
  temperature: 0                 # method/temperature/top_p/top_k/max_tokens/stop/
  max_tokens: 2048               # seed/response_format/reasoning_effort + provider extensions
style: react_intrinsic           # 2.12.0: react_intrinsic is the DEFAULT; `default` & `react` are DEPRECATED
                                 #   (still run, but migrate). Source also exposes planner | custom |
                                 #   experimental_customer_care. Omit `style` to take the tenant default.
hide_reasoning: false
tools:                           # by name; must be imported first
  - get_weather
collaborators:                   # ORCHESTRATOR pattern: other agents used as agents (by name).
  - billing_agent               #   Import/deploy them FIRST. wxO auto-generates a
                                #   chat_with_collaborator_<name> tool; routing is driven by
                                #   each collaborator's `description`. See SKILL §3.3b. Not for
                                #   experimental_customer_care style. (live-verified 2.12.0)
knowledge_base:                  # curated RAG corpora (KB names), ingested by you — distinct
  - product_docs                #   from chat_with_docs (end-user uploads docs in-chat)
toolkits: []                     # only for experimental_customer_care style
guidelines:                      # optional conditional behaviors
  - display_name: Escalate
    condition: user asks for a human
    action: hand off to billing_agent
    tool: billing_agent
structured_output:               # optional JSON schema to force structured replies
  type: object
  properties:
    answer: { type: string }
custom_join_tool: null           # planner style only (mutually exclusive w/ structured_output)
context_access_enabled: true
context_variables: []            # list of non-empty strings
memory_enabled: null             # agentic memory (retain history/context across a session)
is_schedulable: null             # 2.11+ — true enables recurring runs; internal scheduling
                                 #   tools auto-appear (and are visible/deletable via ADK CLI — known issue)
restrictions: null               # 2.11+ — access restrictions
compaction_settings:             # 2.11+ — conversation compaction (prevents context overflow)
  context_compaction_enabled: true
  context_compaction_threshold: 20000   # tokens triggering Level-1 compaction
  compaction_sliding_window: 10         # recent messages kept verbatim
  large_message_threshold: 50000        # token size marking a "large" message
  large_message_chunk_size: 30000
  large_message_target_summary: 10000
  large_message_detect_structured: true
starter_prompts:
  is_default_prompts: false
  prompts:
    - id: default0
      title: Short action title
      subtitle: optional
      prompt: Example clickable prompt
      state: active
welcome_content:
  is_default_message: false
  welcome_message: Welcome to My Agent
  description: One line on what it helps with
chat_with_docs:                  # let END USERS upload documents in-chat and ask over them
  enabled: true                  #   (RAG over user-uploaded files — no pre-ingestion). The
  supports_full_document: true   #   full block (seen on export) carries vector_index
  # vector_index: { chunk_size: 400, chunk_overlap: 50, limit: 10, extraction_strategy: express }
  # generation: { max_docs_passed_to_llm: 5, generated_response_length: Moderate, ... }
  # query_rewrite: { enabled: true }, citations: { ... }, hap_filtering: { ... }
  # → use `enabled: true` to switch on; the rest default sensibly. Distinct from
  #   `knowledge_base:` (curated corpora you ingest). Not for experimental_customer_care.
  # ⚠ RUNTIME (live-verified 2.12.0 SaaS): chat_with_docs ingestion is wired for the
  #   chat UI / embedded web-chat upload widget. Driving it through the runtime
  #   /v1/orchestrate/runs API did NOT make the agent read the uploaded file (even via
  #   the ADK's create_run_with_files) — the doc uploads to S3 but isn't ingested. For
  #   PROGRAMMATIC document RAG, use `knowledge_base:` instead; use chat_with_docs for
  #   interactive end-user uploads via a channel. (ADK RunClient.upload_file_to_s3 also
  #   has a SaaS bug: it POSTs to /v1/upload-to-s3/ → 404; correct is
  #   /v1/orchestrate/upload-to-s3 with NO trailing slash → 200.)
icon: null
is_schedulable: null
```

**Validation rules from source**
- `kind` must equal `native` for a native agent (else `BadRequest`).
- An agent cannot list itself as a collaborator (circular reference).
- `planner` style: provide at most one of `custom_join_tool` / `structured_output`.
- `experimental_customer_care` style: expects `groq/openai/gpt-oss-120b`; does
  **not** support `tools`, `knowledge_base`, `plugins`, `guidelines`,
  `collaborators`, `custom_join_tool`, `chat_with_docs.enabled`.
- `toolkits` are rejected for non-customer-care styles (except the schedulable
  `scheduling_tools` exception).

### External agent (`kind: external`)
A2A / external chat agents. Key fields: `api_url` (required), `auth_scheme`
(`BEARER_TOKEN | API_KEY | NONE`), `auth_config`, `provider`
(`external_chat`, `external_chat/A2A/0.2.1`, `external_chat/A2A/0.3.0`,
`salesforce`, …), `nickname`, `app_id`/`connection_id`, `chat_params`,
`config.enable_cot`, `config.hidden`. Import with `orchestrate agents import -f … --app-id <conn>`.

### Assistant agent (`kind: assistant`)
Wraps a watsonx Assistant. `config` carries `assistant_id`, `crn`,
`service_instance_url`, `environment_id`, `auth_type`
(`MCSP | IBM_CLOUD_IAM | ICP_IAM | BEARER_TOKEN`), `api_key`, `authorization_url`,
`connection_id`; plus top-level `nickname`, `app_id`.

### Defining an agent in Python (alternative to YAML)
```python
from ibm_watsonx_orchestrate.agent_builder.agents import Agent
agent = Agent(
    name="my_agent",
    description="...",
    instructions="...",
    llm="watsonx/meta-llama/llama-3-3-70b-instruct",
    tools=[get_weather],          # PythonTool objects or names
)
agent.dump_spec("agents/my_agent.yaml")   # serialize for CLI import
```

---

## 2. Python tools — `@tool`

```python
from ibm_watsonx_orchestrate.agent_builder.tools import tool, ToolPermission
```

Decorator signature (all optional):
```python
@tool(
    name=...,                 # defaults to function name
    description=...,          # defaults to docstring summary (used for routing)
    permission=ToolPermission.READ_ONLY,   # READ_ONLY | WRITE_ONLY | READ_WRITE | ADMIN
    expected_credentials=[...],             # list[ExpectedCredentials]
    display_name=...,
    input_schema=..., output_schema=...,    # ToolRequestBody/ResponseBody (advanced)
    enable_dynamic_input_schema=False, enable_dynamic_output_schema=False,
    response_format=...,                     # 'content' | 'content_and_artifact'
)
```

### Google-style docstring (parser is strict)
```python
@tool(permission=ToolPermission.READ_WRITE)
def process_request(request_id: str, user_email: str, priority: str = "normal") -> dict:
    """
    Process a service request and create a ticket.

    Args:
        request_id (str): Unique identifier for the request.
        user_email (str): Email of the requesting user.
        priority (str): Priority level (default: normal).
    Returns:
        dict: Result with status and message.
    """
    ...
```
- Summary line, then `Args:`, then `Returns:` with **no blank line between the
  Args and Returns blocks**.
- Every param + return value needs a type hint that matches the docstring type.
- Missing type hints → the parser warns and defaults to `str`.

### Credentials at runtime (never as parameters)
```python
from ibm_watsonx_orchestrate.agent_builder.tools import tool, ToolPermission
from ibm_watsonx_orchestrate.agent_builder.connections import ConnectionType, ExpectedCredentials
from ibm_watsonx_orchestrate.run import connections

APP_ID = "my_api"

@tool(permission=ToolPermission.READ_ONLY,
      expected_credentials=[ExpectedCredentials(app_id=APP_ID, type=ConnectionType.API_KEY_AUTH)])
def call_api(query: str) -> dict:
    """Call the API.

    Args:
        query (str): Search text.
    Returns:
        dict: API response.
    """
    conn = connections.api_key_auth(APP_ID)     # fetch at runtime
    headers = {"Authorization": f"Bearer {conn.api_key}"}
    ...
```
Runtime accessors: `connections.api_key_auth(app_id).api_key`,
`connections.basic(app_id).username/.password`,
`connections.bearer_token(app_id).token`,
`connections.oauth2_auth_code(app_id).access_token`.

### Self-containment
Only stdlib, common third-party (`requests`, `pydantic`, …), and
`ibm_watsonx_orchestrate` imports. **No** `from .x import y` or
`from tools.shared import z`. Define every helper/Pydantic model in the same file.

### Pydantic schemas
Define as explicit classes — never `type('X',(BaseModel,),{...})` (causes
"non-annotated attribute" errors):
```python
from pydantic import BaseModel, Field
class Result(BaseModel):
    status: str = Field(description="Outcome status")
```

---

## 3. Flows — `@flow`

```python
from pydantic import BaseModel
from ibm_watsonx_orchestrate.flow_builder.flows import Flow, flow, START, END

class MyInput(BaseModel):
    city: str

@flow(name="weather_flow", display_name="Weather Flow",
      description="Fetch then format weather", input_schema=MyInput)
def build_weather_flow(aflow: Flow) -> Flow:        # signature is mandatory
    fetch = aflow.tool(get_weather)
    summarize = aflow.prompt(
        name="summarize",
        system_prompt="You format weather data for users.",   # REQUIRED
        user_prompt=["Summarize: {weather}"],
        llm="watsonx/meta-llama/llama-3-3-70b-instruct",
    )
    aflow.sequence(START, fetch, summarize, END)
    return aflow
```

**Node builders**: `aflow.tool(fn)`, `aflow.prompt(...)`, `aflow.user_activity(...)`,
`aflow.docproc(...)`, `aflow.script(...)`, `aflow.agent(...)`, `aflow.if_else(...)`,
`aflow.foreach(...)`. **Wiring**: `aflow.sequence(START, n1, n2, END)` or
`aflow.edge(a, b)`. **Data**: `node.map_input(...)`, `aflow.map_output(...)`.

**New in 2.11–2.12 — flow-builder API (live-verified against ADK 2.12.0 source +
a compiled/imported flow on IBM Cloud SaaS, 2026-06-29):**

Expression syntax everywhere is `flow.input.<field>` / `flow.<var>` (paths must start
with `flow.` and have ≥3 parts). Map a node input with
`node.map_input("<param>", "flow.input.<field>")`.

- **Parallel branches** — `p = aflow.parallel_conditions(name="gather")` (all branches
  run) or `aflow.parallel(evaluator=Conditions(...), ...)`. **Create branch nodes ON
  the parallel node** (`n = p.tool(fn)` / `p.prompt(...)` / `p.sequence(...)`), then
  wire each: `p.condition(to_node=n, default=True)` (always run) or
  `p.condition(expression="flow.input.x=='hi'", to_node=n)`. Parallel runs **all**
  matching conditions concurrently (unlike a branch, which takes the first match).
  `foreach(item_schema=...)` similarly supports a parallel mode.
- **Decision / if-else** — `b = aflow.conditions(name="route")` (empty evaluator) or
  `aflow.branch(name=, evaluator=Conditions([...]) | "expr")`; wire with
  `b.condition(expression="flow.input.severity=='high'", to_node=urgent)` and
  `b.condition(default=True, to_node=routine)`. First match wins.
- **Decision table** — `aflow.decisions(name=, rules=[DecisionsRule(conditions=[...],
  actions={...})], default_actions=...)` for compact rule→action tables.
- **Callbacks** — `aflow.add_callback(tool="<tool_name>", events=[...], batch_interval=None)`.
  Events (`FlowCallbackEventKind`): `ON_FLOW_START`, `ON_FLOW_END`, `ON_FLOW_ERROR`,
  `ON_TASK_ERROR`, `ON_TASK_MESSAGE`, `ON_TASK_WAIT`.
- **Data masking** — `aflow.mask_property(property_path="flow.input.symptoms",
  masking_policy=MaskingPolicy.MASK_ALL)`. Policies: `MASK_ALL`, `MASK_FIRST4`,
  `MASK_LAST4`, `MASK_VIA_REGEX` (pass `regex_config=` for the last). Masked in chat,
  flow inspector, and traces.
- **Timer / scheduling** — `aflow.timer(name=, delay=<seconds:int>, ...)`.
- **Multi-language** — `translation_enabled`, `source_locale`, `target_locales` on the flow.
- ⚠ **Not implemented in 2.12** (raise `ValueError` at build): `aflow.wait_for(...)`;
  `branch(evaluator=<function>)`; Branch `MatchPolicy.ANY_MATCH`. Avoid these.
- ⚠ Platform known issues: parallel branches **pause on user interaction**; multi-step
  user activities running in parallel can break chat prompts.

A complete, compiling reference flow (parallel + decision + masking + prompts) is in the
test project: `test/dr_house_advise/tools/house_triage_flow.py`.

Constraints:
- Function name starts with `build_`, param is `aflow: Flow`, returns `Flow`.
- One flow per file.
- `map_input`/`map_output` expressions are **single-line** Python (list
  comprehensions/inline logic only) — no defining or calling functions; flow-file
  functions are not available at runtime.
- `prompt` nodes require `system_prompt`.

Import a flow as a tool: `orchestrate tools import -k flow -f tools/weather_flow.py`.

### Document processing (docproc) — KVP extraction
Use `DocProcKVPSchema` + `DocProcField` (not plain dicts):
```python
from ibm_watsonx_orchestrate.flow_builder.types import (
    DocProcInput, DocProcKVPSchema, DocProcField, DocProcOutputFormat)

SCHEMA = DocProcKVPSchema(
    document_type="Invoice", document_description="A business invoice",
    additional_prompt_instructions="Extract values exactly as shown.",
    fields={"invoice_number": DocProcField(description="Invoice id", default="", example="INV-001")},
)

@flow(name="doc_flow", input_schema=DocProcInput)
def build_doc_flow(aflow: Flow) -> Flow:
    node = aflow.docproc(name="extract", task="text_extraction",
                         output_format=DocProcOutputFormat.object,
                         kvp_schemas=[SCHEMA], kvp_force_schema_name="Invoice")
    aflow.sequence(START, node, END)
    return aflow
```
With `output_format=object`, `kvps` is a **list** of objects shaped like
`{"key": {"semantic_label": "invoice_number"}, "value": {"raw_text": "INV-001"}}`.
To use values, either pass the whole `kvps` array to a `prompt` node to format,
or extract with a single-line list comprehension matching `semantic_label`.
**Agents cannot pass user-uploaded files to a flow** — the docproc node prompts
the user for the upload itself; agent instructions should just invoke the flow.

**2.11–2.12 docproc updates** (verify flag names with the docs):
- **Page-range extraction** — restrict extraction to specific pages (From/To) instead
  of the whole document; useful for large files where only some pages matter.
- **Default extractor model is now `mistral-small`** (was changed in 2.12); AI-Gateway
  models can be used for KVP extraction.
- **Structured (vision) vs Unstructured (text)** extractors: use structured/vision for
  forms and tables, unstructured/text for text-heavy documents.

### Programmatic flow test
```python
import asyncio
from pathlib import Path
from tools.weather_flow import build_weather_flow

async def main():
    fdef = await build_weather_flow().compile_deploy()
    fdef.dump_spec(f"{Path(__file__).parent}/generated/weather_flow.json")
    await fdef.invoke({"city": "Paris"}, debug=True)

asyncio.run(main())
```
Run with `PYTHONPATH` pointing at the ADK `src` if importing ADK internals.
