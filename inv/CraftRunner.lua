local Object = require 'object.Object'
local CraftPlanner = require 'inv.CraftPlanner'

-- Executes crafting requests using the planner and inventory transfer.
local CraftRunner = Object:subclass()

function CraftRunner:init(server)
    self.server = server
    self.planner = CraftPlanner(server)
end

-- First attempts to pull the requested amount of items out of the network,
-- then attempts to craft any remaining requested items.
function CraftRunner:pushOrCraftItemsTo(criteria, dest, destSlot)
    local n = self.server.inventoryService:pushItemsTo(criteria, dest, destSlot)

    if n < criteria.count then
        local remaining = criteria:copy()
        remaining.count = criteria.count - n
        self.planner:plan(remaining, dest, destSlot)
    end
    return n
end

return CraftRunner
