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
2. Start a client turtle: `run_client.lua SERVER_ID`.
3. Request a workbench-crafted item from the client UI.
4. Confirm items are crafted and delivered.
5. Request a furnace-crafted item.
6. Confirm items are crafted and delivered.

## Expected
- Workbench crafting uses the turtle backend (no errors).
- Furnace crafting uses peripheral backend (no errors).
- Inventory counts update on the client after each craft.
