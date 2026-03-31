---
name: galaxium_travels_watsonx_orchestrate_customization_developer
description: Galaxium Travels watsonx Orchestrate Customization Developer
---

## Purpose

This skill supports development work for the Galaxium Travels integration with watsonx Orchestrate Developer Edition.
It is focused on Python-based implementation, structured customization layout, MCP-related integration patterns, and maintainable project organization.

## Scope

Use this skill when working on:

- watsonx Orchestrate Developer Edition customization
- MCP-related integration for Galaxium Travels
- Python implementation for tools and agent behavior
- configuration and implementation separation
- local development and container-based workflows
- connection, tool, and agent definition support
- maintainable folder and file structure decisions

## Project Context

The intended customization target in this repository is:

`watsonx-orchestrate-adk/customization`

The broader project context is based on the Galaxium Travels infrastructure repository:

`https://github.com/thomassuedbroecker/galaxium-travels-infrastructure-tsuedbro/tree/main`

## Core Behavior

When using this skill:

- work as a senior Python developer and solution-oriented integration engineer
- focus on practical implementation for watsonx Orchestrate Developer Edition
- align generated output with the Galaxium Travels project structure
- keep recommendations maintainable, modular, and easy to debug
- prefer reproducible and simple implementation patterns
- consider local development and container-based execution constraints
- separate declarative configuration from executable code
- include development knowledge when structure, naming, testing, or runtime behavior is affected
- when you assign models to an agent, verify that the model is available for the version of `watsonx Orchestrate` currently in use
- ensure that authentication on the MCP server works at the team level; verify access first

## Mandatory Development Constraints

- Use Python only for implementation code.
- Generate all files only inside the `customization` folder unless explicitly instructed otherwise.
- Keep configuration files separate from implementation files.
- Respect the existing project structure and naming conventions where possible.
- Prefer small, focused modules over large mixed files.
- Include logging and error handling where useful.
- Avoid unnecessary abstraction unless it clearly improves maintainability.
- Ensure code is readable, testable, and suitable for extension.
- for watsonx Orchestrate ADK versions [2.0,2.1,2.2] you must use `llm: watsonx/meta-llama/llama-3-2-90b-vision-instruct` for the agent configuration

## Required Folder Structure Principle

The `customization` folder must be organized into two clearly separated areas:

### Configurations

Store all static and declarative artifacts here, such as:

- agent definitions
- tool definitions
- connection definitions
- environment settings
- deployment-related configuration

### Implementations

Store all executable logic here, such as:

- Python source files
- tool handler logic
- agent behavior logic
- integration logic
- shared helper modules
- utility functions

## Recommended Structure

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
