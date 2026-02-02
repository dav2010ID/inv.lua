local CraftTask = require 'inv.task.CraftTask'

local TaskAssigner = {}

function TaskAssigner.buildBatches(planner, recipe, crafts)
    local machineCount = planner.server.machinePool:countAvailableMachines(recipe.machine)
    local batches = crafts
    if machineCount > 0 then
        batches = math.min(crafts, machineCount)
    else
        batches = 1
    end
    local result = {}
    local remaining = crafts
    for i = 1, batches do
        local batch = math.ceil(remaining / (batches - i + 1))
        table.insert(result, batch)
        remaining = remaining - batch
    end
    return result
end

function TaskAssigner.createTask(planner, recipe, batch, summary, parent, dest, destSlot, depth)
    local priority = -(depth or 0)
    return CraftTask(planner.server, parent, recipe, dest, destSlot, batch, summary, priority)
end

return TaskAssigner
