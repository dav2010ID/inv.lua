# Repository Guidelines

## Project Structure & Module Organization
- `inv/` is the main Lua codebase. It is layered as `core`, `domain`, `craft`, `infrastructure`, `services`, and `runtime`.
- `inv/runtime/Server.lua` is the runtime entrypoint used by `run_server.lua`.
- `config/` holds JSON configuration for devices and recipes, for example `config/devices/minecraft.json` and `config/recipes/user.json`.
- `tools/` contains PowerShell utilities such as dependency checks.
- Root-level scripts like `run_server.lua` and `reproduce_issue.lua` are convenience entrypoints.

## Build, Test, and Development Commands
- `lua run_server.lua <optional CLI command>` runs the server loop in a standard Lua environment. In ComputerCraft, run `run_server` from the in-game shell.
- `lua reproduce_issue.lua` runs a focused regression script with mocked peripherals.
- `powershell -File tools\check_layer_deps.ps1` validates layer dependency rules for `inv/`.
- `powershell -File list_lua_inventory.ps1` generates `lua_inventory_report.txt` for a quick module inventory.

## Coding Style & Naming Conventions
- Indentation is 4 spaces; use single-line `--` comments.
- Files and classes use PascalCase (for example `InventoryService.lua`), and modules are required with single quotes (`require 'inv.domain.Item'`).
- Methods and locals use lowerCamelCase (`getItemCount`, `runTest`).
- Keep module imports at the top of each file and avoid cross-layer imports that violate the `tools/check_layer_deps.ps1` rules.

## Testing Guidelines
- There is no formal test framework. Add or extend small Lua scripts like `reproduce_issue.lua` for regressions.
- Keep tests deterministic and use mocked peripherals or backends where possible.

## Commit & Pull Request Guidelines
- Git history mostly follows a conventional prefix like `feat:` and occasional plain `refactor`. Prefer `type: short summary` with a clear scope.
- If you open a PR, include a concise description, the commands run, and any config changes under `config/`.

## Configuration & Logs
- Runtime logs default to `CraftOSTest.log`; avoid committing large logs.
- Treat `config/recipes/user.json` as user-specific and keep it stable across environments when possible.
