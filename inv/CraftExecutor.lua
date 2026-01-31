local Object = require 'object.Object'
local CraftPlanner = require 'inv.CraftPlanner'

-- Executes crafting requests using the registry and planner.
local CraftExecutor = Object:subclass()

function CraftExecutor:init(server, registry)
    self.server = server
    self.registry = registry
    self.planner = CraftPlanner(server)
end

-- First attempts to pull the requested amount of items out of the network,
-- then attempts to craft any remaining requested items.
function CraftExecutor:pushOrCraftItemsTo(criteria, dest, destSlot)
    local n = self.server.inventoryIO:pushItemsTo(criteria, dest, destSlot)

    if n < criteria.count then
        local remaining = criteria:copy()
        remaining.count = criteria.count - n
        self.planner:plan(remaining, dest, destSlot)
    end
    return n
end

return CraftExecutor
