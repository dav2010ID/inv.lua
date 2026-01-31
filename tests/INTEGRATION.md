# Integration Test: Workbench + Furnace Flow

## Goal
Verify the unified Machine flow works for both a workbench (turtle backend)
and a peripheral crafting machine (e.g., furnace).

## Setup
1. Connect a server turtle with a wired modem.
2. Connect at least one storage inventory (chest) to the network.
3. Connect a workbench peripheral to the server turtle.
4. Connect a furnace (or other crafting machine) to the network.
5. Ensure `config/devices/workbench.json` exists and `config/devices/minecraft.json`
   includes a furnace entry with `"purpose":"crafting"`.
6. Ensure `config/recipes/minecraft.json` contains recipes for workbench and furnace.

## Steps
1. Start the server: `run_server.lua`.
2. Use CLI: `craft minecraft:oak_planks 4` (or any workbench recipe).
3. Confirm items are crafted and stored.
4. Use CLI: `craft minecraft:stone 8` (or any furnace recipe).
5. Confirm items are crafted and stored.

## Expected
- Workbench crafting uses the turtle backend (no errors).
- Furnace crafting uses peripheral backend (no errors).
- Inventory counts update after each craft (`list` or `count`).
