# 1. Set Up The Galaxium Travels Infrastructure

This repository keeps the walkthrough files at the root, but the runnable Galaxium
stack still comes from the separate infrastructure repository.

Use this guide to:

- clone that infrastructure repository into `./infrastructure/`
- start the Basic Auth stack used by guides `2` and `4`

## 1.1 Prerequisites

- Docker Desktop, Rancher Desktop, or another working Docker runtime
- `git`
- `curl` and `jq`
- `npx` if you plan to use MCP Inspector in guide `3`

## 1.2 Clone The Infrastructure Repository

From the root of this repository:

```sh
cd infrastructure
git clone https://github.com/thomassuedbroecker/galaxium-travels-infrastructure-tsuedbro.git
cd galaxium-travels-infrastructure-tsuedbro
```

If you already cloned it earlier, just enter:

```sh
cd infrastructure/galaxium-travels-infrastructure-tsuedbro
```

## 1.3. Basic Auth Stack For Guides 2 And 4

Use this mode when you want:

- the MCP backend protected by shared Basic Auth
- the manual backend verification from guide `2`
- the `watsonx Orchestrate` remote MCP import from guide `4`

### 1.3.1 Prepare The Env File

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
```

Default demo credentials:

- username: `demo-basic-user`
- password: `demo-basic-password`

### 1.3.2 Optional Smoke Checks

These scripts start their own short-lived test stacks and verify the current setup:

```sh
bash local-container/verify-basic-auth-backends.sh
bash local-container/verify-basic-auth-frontends-and-inspector.sh
```

### 1.3.3 Start The Running Basic Auth Stack

VM-style variant using the local network and not the host network:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth-vm.yaml \
  up --build 
```

### 1.3.4 Basic Auth URLs

- Booking REST API docs: `http://localhost:8082/docs`
- REST web UI: `http://localhost:8083`
- MCP endpoint: `http://localhost:8084/mcp`
- MCP web UI: `http://localhost:8085`

### [Home](./README.md)
