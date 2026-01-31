# TODO: Modularity + Machine/Workbench Unification

## Goals
- Improve modularity of crafting devices.
- Merge Workbench behavior into Machine via configuration/strategy.

## Tasks
- Extract a "craft backend" strategy interface (e.g., `craft`, `getItemDetail`, `mapSlot`, `locationResolver`).
- Represent Workbench as a Machine config (e.g., `backend = "turtle"`) instead of a separate class.
- Unify slot mapping: Machine always calls `mapSlot`; Workbench uses a predefined slot map via config.
- Move Workbench-specific `location = Common.getNameLocal()` into backend strategy.
- Simplify `DeviceManager:createDevice`: single Machine path for all crafting devices.
- Add common inventory IO adapter (optional) for `list/push/pull/getItemDetail` to reduce duplication.
- Normalize `getItemDetail` behavior (peripheral vs turtle) inside backend strategy.
- Define a clear machines config schema (purpose, backend, slots, location).
- Add an integration test (workbench recipe + furnace recipe) to exercise the unified Machine flow.
