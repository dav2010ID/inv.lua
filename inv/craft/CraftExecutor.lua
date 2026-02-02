local Object = require 'inv.core.Object'
local CraftPlanner = require 'inv.craft.CraftPlanner'
local TaskFactory = require 'inv.craft.TaskFactory'

-- Executes crafting requests using the planner and inventory transfer.
local CraftExecutor = Object:subclass()

function CraftExecutor:init(server)
    self.server = server
    self.planner = CraftPlanner(server)
    self.factory = TaskFactory(server)
end

-- First attempts to pull the requested amount of items out of the network,
-- then attempts to craft any remaining requested items.
function CraftExecutor:pushOrCraftItemsTo(criteria, dest, destSlot)
    local n = self.server.inventoryService:push(dest, criteria, criteria.count, destSlot)

    if n < criteria.count then
        local remaining = criteria:copy()
        remaining.count = criteria.count - n
        local plan = self.planner:plan(remaining)
        if plan then
            self.factory:queuePlan(plan, dest, destSlot)
        else
            self.server.logger.warn("[craft] no recipe for", remaining.name or "unknown")
        end
    end
    return n
end

return CraftExecutor

