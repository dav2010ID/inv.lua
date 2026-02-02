local Class = require 'inv.core.Class'
local CraftTask = require 'inv.domain.CraftTask'
local WaitTask = require 'inv.domain.WaitTask'
local CraftGraph = require 'inv.domain.CraftGraph'

local TaskFactory = Class:subclass()
local TaskGraphBuilder = Class:subclass()
local TaskQueue = Class:subclass()

function TaskFactory:init(server)
    self.server = server
end

function TaskFactory:createTask(recipe, batch, summary, parent, dest, destSlot, depth)
    local priority = -(depth or 0)
    return CraftTask(self.server, parent, recipe, dest, destSlot, batch, summary, priority)
end

function TaskGraphBuilder:init(server, queue)
    self.server = server
    self.logger = server.logger
    self.queue = queue
    self.maxDepth = 32
end

function TaskGraphBuilder:addWaitTask(parent, item, summaryId)
    local task = WaitTask(self.server, parent, item)
    if summaryId then
        task.summaryId = summaryId
    end
    self.queue:schedule(task)
end

function TaskGraphBuilder:link(task, recipe, depth, visiting, craftCount, summaryId)
    CraftGraph.link(self, task, recipe, depth, visiting, craftCount, summaryId)
end

function TaskQueue:init(server)
    self.server = server
    self.logger = server.logger
    self.taskFactory = TaskFactory(server)
    self.taskGraphBuilder = TaskGraphBuilder(server, self)
end

function TaskQueue:resolveSummary(summaryRef)
    if not summaryRef then
        return nil
    end
    if type(summaryRef) == "table" then
        return summaryRef
    end
    return self.server.taskScheduler.summaries[summaryRef]
end

function TaskQueue:buildBatches(recipe, crafts)
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

function TaskQueue:schedule(task)
    self.server.taskScheduler:addTask(task)
end

function TaskQueue:enqueueRecipe(recipe, crafts, summaryRef, parent, dest, destSlot, depth, visiting, skipDependencies)
    local summary = self:resolveSummary(summaryRef)
    local batches = self:buildBatches(recipe, crafts)
    for i = 1, #batches do
        local batch = batches[i]
        local task = self.taskFactory:createTask(recipe, batch, summary, parent, dest, destSlot, depth)
        self.server.taskScheduler:registerTask(summary, task)
        if not skipDependencies then
            self.taskGraphBuilder:link(task, recipe, depth, visiting, batch, summary and summary.id or summaryRef)
            task.dependenciesPlanned = true
        end
        self:schedule(task)
    end
end

function TaskQueue:queuePlan(plan, dest, destSlot)
    local summary = self.server.taskScheduler:createSummary(plan.criteria, plan.crafts)
    self:enqueueRecipe(plan.recipe, plan.crafts, summary, nil, dest, destSlot, 0, {}, false)
    self.server.machineScheduler:setCriticalMachine()
    self.server.machineScheduler:logMachineSummary()
    return summary
end

return {
    TaskFactory = TaskFactory,
    TaskGraphBuilder = TaskGraphBuilder,
    TaskQueue = TaskQueue
}
