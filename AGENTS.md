# AGENTS.md
This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common commands
- Run the server (on the crafting turtle, from the repo directory): `run_server.lua`
- Optional auto-start (create `startup.lua` in turtle root):
  - `shell.setDir("inv")`
  - `shell.run("run_server.lua")`
- Server CLI commands (at runtime): `help`, `list [filter]`, `count <item>`, `craft <item> <count>`, `scan`, `devices`, `status`, `quit`

Note: README/ARCHITECTURE do not document build, lint, or test commands.

## Architecture overview
- Layering (enforced by convention):  
  - `core`: runtime utilities (no dependencies)  
  - `domain`: pure model/state (depends on `core`)  
  - `craft`, `services`: business logic (depend on `domain` + `core`)  
  - `infrastructure`: peripherals/IO/network (depends on `core` + `domain`)  
  - `runtime`: composition + main loop (depends on all layers)
- Module layout mirrors layers under `inv/`:
  - `inv/core`, `inv/domain`, `inv/craft`, `inv/services`, `inv/infrastructure`, `inv/runtime`
- OOP base: `inv/core/Class.lua` (runtime support only; no business rules).
- Device wiring:
  - `inv/infrastructure/DeviceCatalog.lua` creates devices based on config.  
  - Storage/Machine base classes are in `inv/infrastructure/device/`.
  - Machine backends are registered via `inv/infrastructure/machine/BackendRegistry.lua`.

## Configuration & runtime notes
- Config lives in `config/devices/*.json` and `config/recipes/*.json`.  
- Run from the repo directory so config files are found.
- CC:Tweaked “generic peripherals” must be enabled.
