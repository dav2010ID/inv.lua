local Object = require 'object.Object'
local CraftTask = require 'inv.domain.CraftTask'
local BlockedTask = require 'inv.domain.BlockedTask'
local CraftDependencyGraph = require 'inv.craft.CraftDependencyGraph'

local TaskFactory = Object:subclass()

function TaskFactory:init(server)
    self.server = server
    self.logger = server.logger
    self.maxDepth = 32
end

function TaskFactory:buildBatches(recipe, crafts)
    local machineCount = self.server.machineRegistry:countAvailableMachines(recipe.machine)
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

function TaskFactory:createTask(recipe, batch, summary, parent, dest, destSlot, depth)
    local priority = -(depth or 0)
    return CraftTask(self.server, parent, recipe, dest, destSlot, batch, summary, priority)
end

function TaskFactory:resolveSummary(summaryRef)
    if not summaryRef then
        return nil
    end
    if type(summaryRef) == "table" then
        return summaryRef
    end
    return self.server.taskScheduler.summaries[summaryRef]
end

function TaskFactory:addBlockedTask(parent, item, summaryId)
    local task = BlockedTask(self.server, parent, item)
    if summaryId then
        task.summaryId = summaryId
    end
    self.server.taskScheduler:addTask(task)
end

function TaskFactory:queueRecipe(recipe, crafts, summaryRef, parent, dest, destSlot, depth, visiting, skipDependencies)
    local summary = self:resolveSummary(summaryRef)
    local batches = self:buildBatches(recipe, crafts)
    local remaining = crafts
    for i = 1, #batches do
        local batch = batches[i]
        local task = self:createTask(recipe, batch, summary, parent, dest, destSlot, depth)
        self.server.taskScheduler:registerTask(summary, task)
        if not skipDependencies then
            CraftDependencyGraph.attachDependencies(self, task, recipe, depth, visiting, batch, summary and summary.id or summaryRef)
            task.dependenciesPlanned = true
        end
        self.server.taskScheduler:addTask(task)
        remaining = remaining - batch
    end
end

function TaskFactory:queuePlan(plan, dest, destSlot)
    local summary = self.server.taskScheduler:createSummary(plan.criteria, plan.crafts)
    self:queueRecipe(plan.recipe, plan.crafts, summary, nil, dest, destSlot, 0, {}, false)
    self.server.machineScheduler:setCriticalMachine()
    self.server.machineScheduler:logMachineSummary()
    return summary
end

function TaskFactory:attachDependencies(task, recipe, depth, visiting, craftCount, summaryId)
    CraftDependencyGraph.attachDependencies(self, task, recipe, depth, visiting, craftCount, summaryId)
end

return TaskFactory
