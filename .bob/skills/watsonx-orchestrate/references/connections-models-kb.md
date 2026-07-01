# Connections, Models (watsonx.ai AI Gateway) & Knowledge Bases

---

## 1. Connections

A connection stores credentials/config for an external service, referenced by
`app_id`. Two halves: a **YAML definition** (structure) and **credentials** set
separately via the CLI. Never put real secrets in YAML.

### Connection YAML

```yaml
spec_version: v1
kind: connection            # singular!
app_id: my_api              # unique id; tools reference this
environments:
  draft:                    # at least 'draft' required; 'live' for production
    security_scheme: api_key_auth   # NOT 'kind' here
    type: team              # team (shared) | member (per-user)
    server_url: https://api.example.com
```

`security_scheme` values: `basic_auth`, `bearer_token`, `api_key_auth`,
`oauth2`, `key_value_creds`.

OAuth2 example (note `auth_type`):
```yaml
spec_version: v1
kind: connection
app_id: google_sheets
environments:
  draft:
    security_scheme: oauth2
    auth_type: oauth2_auth_code         # NOT 'authorization_code'
    type: team
    server_url: https://sheets.googleapis.com
    auth_url: https://accounts.google.com/o/oauth2/v2/auth
    token_url: https://oauth2.googleapis.com/token
    scope:
      - https://www.googleapis.com/auth/spreadsheets.readonly
```

### CLI lifecycle

```bash
orchestrate connections add --app-id my_api
orchestrate connections configure -a my_api --kind api_key --type team --env draft
orchestrate connections set-credentials -a my_api --env draft --api-key "$MY_KEY"
# basic auth:
orchestrate connections set-credentials -a my_api --env draft -u "$USER" -p "$PASS"
# key/value entries:
orchestrate connections set-credentials -a my_api --env draft --entries "api_key=$KEY"
orchestrate connections list
```

`--kind` (configure) values: `basic | bearer | api_key | key_value | kv |
oauth_auth_code_flow | oauth_auth_password_flow |
oauth_auth_client_credentials_flow | oauth_auth_on_behalf_of_flow |
oauth_auth_token_exchange_flow | oauth_auth_direct_access_flow`.

**Tip:** keep secrets in a gitignored `.env`, `source ./.env`, and pass via
`--api-key "$VAR"` / `--entries "k=$VAR"` so they stay out of shell history.

Connection types used in tool `ExpectedCredentials`: `ConnectionType.BASIC_AUTH`,
`BEARER_TOKEN`, `API_KEY_AUTH`, `OAUTH2_AUTH_CODE`, `OAUTH2_PASSWORD`,
`OAUTH2_CLIENT_CREDS`, `KEY_VALUE`.

---

## 2. Models via the watsonx.ai AI Gateway

List what the active env offers, then reference by full id in agent YAML:
```bash
orchestrate models list
```
Examples: `watsonx/meta-llama/llama-3-3-70b-instruct`,
`watsonx/ibm/granite-3-3-8b-instruct`, `groq/openai/gpt-oss-120b`.

### Adding your own watsonx.ai model

**Provider config schema** (`provider_config` / connection entries):
```jsonc
{
  "api_key": "string",                 // required
  "watsonx_space_id": "string",        // need at least one of space/project/deployment
  "watsonx_project_id": "string",
  "watsonx_deployment_id": "string",
  "watsonx_cpd_url": "string",         // on-prem (CPD) only
  "watsonx_cpd_username": "string",    // on-prem (CPD) only
  "watsonx_cpd_password": "string",    // on-prem (CPD) only
  "watsonx_version": "string",
  "custom_host": "string",
  "request_timeout": 30,
  "transform_to_form_data": false
}
```

**Steps**
```bash
# 1) credentials connection for watsonx.ai
orchestrate connections add --app-id watsonx_credentials
orchestrate connections configure -a watsonx_credentials --kind key_value --type team --env draft
source ./.env
orchestrate connections set-credentials -a watsonx_credentials --env draft \
  --entries "api_key=${WATSONX_APIKEY}"
# add watsonx_space_id / watsonx_project_id / watsonx_deployment_id as needed
```

```yaml
# 2) models/granite.yaml
spec_version: v1
kind: model
name: watsonx/ibm/granite-3-3-8b-instruct
display_name: IBM watsonx.ai (Granite)
description: IBM watsonx.ai model using Space-scoped configuration.
tags: [ibm, watsonx]
model_type: chat
provider_config:
  watsonx_space_id: my-space-id
```

```bash
# 3) import
orchestrate models import -f models/granite.yaml --app-id watsonx_credentials
# 4) (optional) make it the tenant default (2.10.0: under `models config`)
orchestrate models config default
```

If import warns about missing required fields (e.g. `api_key`), re-run
`set-credentials` to add the missing entries. Keep the model `name` stable across
environments; only `provider_config` / credentials differ between dev/stage/prod.

---

## 3. Knowledge bases (RAG)

### Built-in Milvus (managed — default choice)
```yaml
spec_version: v1
kind: knowledge_base
name: product_docs
description: Product documentation for grounding answers.
documents:
  - path: doc1.pdf
  - path: doc2.pdf
vector_index:
  embeddings_model_name: ibm/slate-125m-english-rtrvr-v2
```
No external infra; supports PDF/DOCX/PPTX/XLSX/CSV/HTML/TXT.
`orchestrate knowledge-bases import -f kb.yaml` then
`orchestrate knowledge-bases status -n product_docs` to watch ingestion.

### External providers (`conversational_search_tool.index_config`)
Set `prioritize_built_in_index: false` and an `app_id` connection.

- **AstraDB** — `astradb:` block (`api_endpoint`, `collection`/`table`,
  `embedding_model_id`, `embedding_mode: server|client`, `search_mode:
  vector|lexical|hybrid`, `field_mapping`). Auth: **API key**.
- **External Milvus** — `milvus:` block (`endpoint`, `collection_name`,
  `embedding_provider`, `embedding_model`, `embedding_dimension`, `field_mapping`).
  Auth: **basic**.
- **Elasticsearch** — `elasticsearch:` block (`endpoint`, `index_name`,
  `embedding_field`, `field_mapping`). Auth: **API key or basic**.

Example (Elasticsearch):
```yaml
spec_version: v1
kind: knowledge_base
name: es_kb
description: KB on Elasticsearch
app_id: es_conn
prioritize_built_in_index: false
conversational_search_tool:
  index_config:
    - elasticsearch:
        endpoint: 'https://es.example.com'
        index_name: my_index
        embedding_field: vector_embedding
        field_mapping: { title: title, body: content, url: url }
```

### Unsupported stores → custom RAG tool
For Pinecone, Weaviate, Qdrant, Chroma, proprietary search, etc., **don't** use a
knowledge base — write a Python `@tool` that queries the store and returns
results, then attach it to the agent and instruct it to cite sources. (Pattern in
agents-tools-schemas.md.)

### Reference an agent to a KB
```yaml
knowledge_base:
  - product_docs
```

### Decision tree
```
Existing vector DB?
├─ No → Built-in Milvus (managed)
└─ Yes → AstraDB / Milvus / Elasticsearch provider blocks
         else (Pinecone/Weaviate/Qdrant/Chroma/custom) → custom Python @tool
```
