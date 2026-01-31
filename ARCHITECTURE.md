# inv.lua Architecture

## Overview
- Purpose: inventory management and auto-crafting for CC:Tweaked turtles, using a central server with a built-in CLI.
- Communication: device discovery and IO via the modem network; no client protocol required.
- Configuration: JSON files under `config/` define devices and recipes.

## Entry points
- `run_server.lua`: starts the inventory/crafting server loop via `inv/Server.lua`.

## Directory layout
- `config/`
  - `devices/`: device overrides, purpose (storage/crafting), backend, priorities, filters, slot mapping.
  - `recipes/`: crafting recipes for workbench/machines.
- `inv/`: core inventory system, server logic, managers, and domain models.
  - `device/`: peripheral abstractions (Storage, Machine).
  - `task/`: async task system (CraftTask, WaitTask, Task base).
- `object/`: lightweight OOP base class with inheritance utilities.

## Core runtime components

### Server side (`inv/Server.lua`)
- **Server**: bootstraps config, managers, recipes, devices; owns the main event loop.
- **DeviceManager** (`inv/DeviceManager.lua`): scans peripherals, creates Device instances, applies config overrides.
- **StorageManager** (`inv/StorageManager.lua`): tracks storage devices and sorting order.
- **InventoryIndex** (`inv/InventoryIndex.lua`): authoritative item database; tracks counts/tags and update flags.
- **InventoryIO** (`inv/InventoryIO.lua`): scanning and item push/pull across storage devices.
- **CraftRegistry** (`inv/CraftRegistry.lua`): stores recipes and crafting machines.
- **CraftExecutor** (`inv/CraftExecutor.lua`): fulfills requests using inventory IO and the planner.
- **CraftPlanner** (`inv/CraftPlanner.lua`): builds dependency DAGs for crafting tasks.
- **TaskManager** (`inv/TaskManager.lua`): schedules async tasks and handles sub-task dependencies.

### Device layer (`inv/device/*`)
- **Device**: base wrapper around a peripheral with `getItemDetail` and `destroy` hooks.
- **Storage**: inventory device; honors filters and priority; supports push/pull/list.
- **Machine**: crafting machine with slot mapping and backend strategy (peripheral or turtle).
### CLI control
- Server uses a built-in CLI for listing items and queuing crafts.

### Domain models
- **Item** (`inv/Item.lua`): matching rules (by name/tags), stacking logic.
- **Recipe** (`inv/Recipe.lua`): input/output definitions for a specific machine type.

## Data and control flow
1. **Server startup**
   - Loads device and recipe config from `config/`.
   - Builds recipes, scans peripherals, registers storage and crafting machines.
2. **Crafting requests**
   - CLI command queues crafting tasks if needed.
3. **Inventory updates**
   - `InventoryIndex` tracks changed items for internal state.
4. **Crafting tasks**
   - `CraftPlanner` builds a dependency tree; `CraftTask` executes once inputs are available.
   - Machines pull outputs back into storage, optionally forwarding to a destination.

## Extension points
- Add new device behaviors by introducing a new class in `inv/device/` and updating `DeviceManager:createDevice`.
- Add new recipe sets via additional JSON files under `config/recipes/`.
- Extend CLI commands in `inv/Server.lua`.
