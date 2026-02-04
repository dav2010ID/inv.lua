local Class = require 'inv.core.Class'
local CraftTask = require 'inv.domain.CraftTask'
local Task = require 'inv.domain.Task'
local CraftGraph = require 'inv.domain.CraftGraph'

local TaskFactory = Class:subclass()
local TaskGraphBuilder = Class:subclass()
local TaskQueue = Class:subclass()

local PRIORITY_ALPHA = 1.4

function TaskFactory:init(server)
    self.server = server
end

function TaskFactory:estimateDuration(recipe, craftCount)
    local registry = self.server and self.server.machineRegistry or nil
    if not registry or not recipe then
        return nil
    end
    local machine = registry:getAny(recipe.machine)
    if not machine or type(machine.estimateDuration) ~= "function" then
        return nil
    end
    return machine:estimateDuration(recipe, craftCount)
end

function TaskFactory:createTask(recipe, batch, summary, parent, dest, destSlot, depth)
    local estimatedDuration = self:estimateDuration(recipe, batch)
    local basePriority = (estimatedDuration or 0) + 1
    local remainingDepth = (depth or 0) + 1
    local remainingTime = basePriority
    if parent and parent.remainingTime then
        remainingTime = remainingTime + parent.remainingTime
    end
    local weight = remainingTime > 0 and (remainingTime ^ PRIORITY_ALPHA) or remainingDepth
    local priority = basePriority * weight
    local task = CraftTask(self.server, parent, recipe, dest, destSlot, batch, summary, priority)
    task.estimatedDuration = estimatedDuration
    task.remainingDepth = remainingDepth
    task.remainingTime = remainingTime
    task.priorityBase = basePriority
    task.priorityWeight = weight
    return task
end

function TaskGraphBuilder:init(server, queue)
    self.server = server
    self.logger = server.logger
    self.queue = queue
    self.maxDepth = 32
end

function TaskGraphBuilder:addWaitTask(parent, item, summaryId, reason)
    local task = Task(self.server, parent)
    task.waitItem = item
    task.waitReason = reason
    if summaryId then
        task.summaryId = summaryId
    end
    self.queue:schedule(task)
end

function TaskGraphBuilder:graphContext()
    return {
        inventoryQuery = self.server.inventoryQuery,
        recipeStore = self.server.recipeStore,
        logger = self.logger,
        maxDepth = self.maxDepth,
        addWait = function(parent, item, summaryId, reason)
            self:addWaitTask(parent, item, summaryId, reason)
        end,
        enqueueRecipe = function(parent, recipe, crafts, depth, visiting, summaryId)
            self.queue:enqueueRecipe(recipe, crafts, summaryId, parent, nil, nil, depth, visiting, false)
        end,
        registerDependency = function(fromMachine, toMachine, summaryId)
            if self.server and self.server.taskScheduler and fromMachine and toMachine then
                self.server.taskScheduler:registerMachineDependency(summaryId, fromMachine, toMachine)
            end
        end,
        identityKey = function(item)
            if item and item.identityKey then
                return item:identityKey()
            end
            return tostring(item)
        end
    }
end

function TaskGraphBuilder:link(task, recipe, depth, visiting, craftCount, summaryId)
    local ctx = self:graphContext()
    return CraftGraph.link(ctx, task, recipe, depth, visiting, craftCount, summaryId)
end

function TaskQueue:init(server)
    self.server = server
    self.logger = server.logger
    self.taskFactory = TaskFactory(server)
    self.taskGraphBuilder = TaskGraphBuilder(server, self)
end

function TaskQueue:shouldDeferMachine(machineType)
    if not machineType then
        return false
    end
    if self.server and self.server.machineScheduler and self.server.machineScheduler.deferMachineTypes then
        if self.server.machineScheduler.deferMachineTypes[machineType] then
            return true
        end
    end
    return string.find(string.lower(machineType), "assembler", 1, true) ~= nil
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
    local machineCount = self.server.machineScheduler:countAvailableMachines(recipe.machine)
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
    local planId = summary and summary.id or summaryRef or 0
    local batchKey = tostring(planId) .. ":" .. tostring(recipe.machine)
    for i = 1, #batches do
        local batch = batches[i]
        local task = self.taskFactory:createTask(recipe, batch, summary, parent, dest, destSlot, depth)
        task.batchMachine = recipe.machine
        task.batchIndex = i
        task.batchKey = batchKey
        task.batchPlanId = planId
        self.server.taskScheduler:registerTask(summary, task)
        if self.logger then
            self.logger.debug(
                "[task] enqueue",
                recipe.machine,
                "x" .. tostring(task.craftCount),
                "priority",
                string.format("%.2f", task.priority or 0),
                "weight",
                string.format("%.2f", task.priorityWeight or 0),
                "base",
                string.format("%.2f", task.priorityBase or 0)
            )
        end
        if not skipDependencies then
            local result = self.taskGraphBuilder:link(task, recipe, depth, visiting, batch, summary and summary.id or summaryRef)
            if result and result.added == 0 and result.blocked == 0 then
                task.needsDependencies = true
            else
                task.needsDependencies = false
            end
        else
            task.needsDependencies = true
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
