local Class = require 'inv.core.Class'
local CraftPlanner = require 'inv.craft.CraftPlanner'
local TaskFactory = require 'inv.craft.TaskFactory'

-- Executes crafting requests using the planner and inventory transfer.
local CraftExecutor = Class:subclass()

function CraftExecutor:init(server)
    self.server = server
    self.planner = CraftPlanner(server)
    self.taskQueue = TaskFactory.TaskQueue(server)
    self.taskGraphBuilder = self.taskQueue.taskGraphBuilder
end

-- First attempts to pull the requested amount of items out of the network,
-- then attempts to craft any remaining requested items.
function CraftExecutor:pushOrCraftItemsTo(criteria, dest, destSlot)
    local n = self.server.inventoryMutator:push(dest, criteria, criteria.count, destSlot)

    if n < criteria.count then
        local remaining = criteria:copy()
        remaining.count = criteria.count - n
        local plan = self.planner:plan(remaining)
        if plan then
            self.taskQueue:queuePlan(plan, dest, destSlot)
        else
            self.server.logger.warn("[craft] no recipe for", remaining.name or "unknown")
        end
    end
    return n
end

return CraftExecutor



