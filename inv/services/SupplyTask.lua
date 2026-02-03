local Task = require 'inv.domain.Task'

-- Orchestrates fulfilling a supply request (services layer).
local SupplyTask = Task:subclass()

SupplyTask.states = {
    supplying = true,
    planning = true,
    waiting = true,
    done = true
}

function SupplyTask:init(server, parent, criteria, dest, destSlot)
    SupplyTask.superClass.init(self, server, parent)
    self.criteria = criteria
    self.dest = dest
    self.destSlot = destSlot
    self.remaining = criteria.count
    self.state = "supplying"
end

local function criteriaForRemaining(task)
    local remaining = task.criteria:copy()
    remaining.count = task.remaining
    return remaining
end

local function planCraftBatches(task, plan)
    local queue = task.server.craftExecutor and task.server.craftExecutor.taskQueue or nil
    if not queue then
        return false
    end
    queue:enqueueRecipe(plan.recipe, plan.crafts, nil, task, task.dest, task.destSlot, 0, {}, false)
    return true
end

function SupplyTask:isSatisfied()
    return self.remaining <= 0
end

function SupplyTask:trySupplyFromInventory()
    if self.remaining <= 0 then
        return true
    end
    local remaining = criteriaForRemaining(self)
    local moved = self.server.inventoryMutator:push(self.dest, remaining, remaining.count, self.destSlot)
    self.remaining = math.max(0, self.remaining - moved)
    return self.remaining <= 0
end

function SupplyTask:ensureProductionPlanned()
    if self.remaining <= 0 then
        return true
    end
    local remaining = criteriaForRemaining(self)
    local planner = self.server.craftExecutor and self.server.craftExecutor.planner or nil
    if not planner then
        return false
    end
    local plan, reason = planner:planWithReason(remaining)
    if plan then
        planCraftBatches(self, plan)
    else
        local waitReason = reason or "no_recipe"
        local waitTask = Task(self.server, self)
        waitTask.waitItem = remaining
        waitTask.waitReason = waitReason
        self.server.taskScheduler:addTask(waitTask)
    end
    self.state = "waiting"
    self.server.taskScheduler:setStatus(self, "waiting", "subtasks")
    return true
end

function SupplyTask:run()
    if self.state == "waiting" then
        self.state = "supplying"
    end

    if self.state == "supplying" then
        if self:trySupplyFromInventory() then
            self.state = "done"
            return true
        end
        self.state = "planning"
    end

    if self.state == "planning" then
        self:ensureProductionPlanned()
        return false
    end

    if self.state == "done" then
        return true
    end

    return false
end

return SupplyTask
