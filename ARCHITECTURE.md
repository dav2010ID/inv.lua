# inv.lua Architecture

## Overview
- Purpose: inventory management and auto-crafting for CC:Tweaked turtles, using a central server and multiple clients.
- Communication: rednet messages over a modem network, protocol name "inv" (see `inv/Common.lua`).
- Configuration: JSON files under `config/` define devices and recipes.

## Entry points
- `run_server.lua`: starts the inventory/crafting server loop via `inv/Server.lua`.
- `run_client.lua`: starts a client UI for requesting/storing items via `inv/Client.lua`.

## Directory layout
- `config/`
  - `devices/`: device overrides, purpose (storage/crafting), backend, priorities, filters, slot mapping.
  - `recipes/`: crafting recipes for workbench/machines.
- `gui/`: custom GUI toolkit used by the client UI (widgets, containers, scrollbars, etc.).
- `inv/`: core inventory system, client/server logic, managers, RPC, and domain models.
  - `device/`: peripheral abstractions (Storage, Machine, ClientDevice).
  - `task/`: async task system (CraftTask, WaitTask, Task base).
- `object/`: lightweight OOP base class with inheritance utilities.

## Core runtime components

### Server side (`inv/Server.lua`)
- **Server**: bootstraps config, managers, recipes, devices; owns the main event loop.
- **DeviceManager** (`inv/DeviceManager.lua`): scans peripherals, creates Device instances, applies config overrides.
- **StorageManager** (`inv/StorageManager.lua`): tracks storage devices and sorting order.
- **InvManager** (`inv/InvManager.lua`): authoritative item database; tracks counts/tags; push/pull items to storage.
- **CraftManager** (`inv/CraftManager.lua`): stores recipes and crafting machines; queues crafts when items are missing.
- **CraftPlanner** (`inv/CraftPlanner.lua`): builds dependency DAGs for crafting tasks.
- **TaskManager** (`inv/TaskManager.lua`): schedules async tasks and handles sub-task dependencies.
- **RPCMethods** (`inv/RPCMethods.lua`): rednet endpoints for list/request/store/unregister.

### Device layer (`inv/device/*`)
- **Device**: base wrapper around a peripheral with `getItemDetail` and `destroy` hooks.
- **Storage**: inventory device; honors filters and priority; supports push/pull/list.
- **Machine**: crafting machine with slot mapping and backend strategy (peripheral or turtle).
- **ClientDevice**: represents a client turtle connected to the network.

### Client side (`inv/Client.lua`, `inv/ClientUI.lua`)
- **Client**: sends RPC calls, deposits items, requests items, and manages local item cache.
- **ClientUI**: GUI for listing items and requesting/storing them; built on `gui/` toolkit.

### Domain models
- **Item** (`inv/Item.lua`): matching rules (by name/tags), serialization for clients, stacking logic.
- **Recipe** (`inv/Recipe.lua`): input/output definitions for a specific machine type.

## Data and control flow
1. **Server startup**
   - Loads device and recipe config from `config/`.
   - Builds recipes, scans peripherals, registers storage and crafting machines.
2. **Client startup**
   - Opens rednet modem, requests initial item list from server.
3. **Requesting items**
   - Client calls `requestItem` RPC.
   - Server attempts to push items from storage; if short, queues crafting tasks.
4. **Storing items**
   - Client calls `storeItems` with slot details.
   - Server pulls items into storage respecting filters/priority.
5. **Inventory updates**
   - `InvManager` tracks changed items and Server broadcasts deltas to all clients.
6. **Crafting tasks**
   - `CraftTask` checks dependencies; may spawn sub-tasks or wait for missing items.
   - Machines pull outputs back into storage, optionally forwarding to a destination.

## Extension points
- Add new device behaviors by introducing a new class in `inv/device/` and updating `DeviceManager:createDevice`.
- Add new recipe sets via additional JSON files under `config/recipes/`.
- Extend client UI by composing new widgets in `inv/ClientUI.lua` using `gui/`.
