local Object = require 'object.Object'
local DependencyResolver = require 'inv.craft.DependencyResolver'
local TaskAssigner = require 'inv.craft.TaskAssigner'

-- Builds a dependency tree (DAG) of crafting tasks before execution.
local CraftPlanner = Object:subclass()

function CraftPlanner:init(server)
    self.server = server
    self.logger = server.logger
    self.maxDepth = 32
end

function CraftPlanner:plan(criteria, dest, destSlot)
    local recipe = self.server.craftRegistry:findRecipe(criteria)
    if not recipe then
        return 0
    end

    local nOut = DependencyResolver.findOutputCount(recipe, criteria)
    if nOut <= 0 then
        return 0
    end

    local crafts = math.ceil(criteria.count / nOut)
    self.logger.info("[planner] plan", crafts, "craft(s) on", recipe.machine, "at", string.format("%.2fs", os.clock()))
    local summary = self.server.taskManager:createSummary(criteria, crafts)
    self:queueTasks(recipe, crafts, summary, nil, dest, destSlot, 0, {}, false)
    self:setCriticalMachine()
    self:logMachineSummary()
    return crafts
end

function CraftPlanner:queueTasks(recipe, crafts, summary, parent, dest, destSlot, depth, visiting, skipDependencies)
    local batches = TaskAssigner.buildBatches(self, recipe, crafts)
    local remaining = crafts
    for i = 1, #batches do
        local batch = batches[i]
        local task = TaskAssigner.createTask(self, recipe, batch, summary, parent, dest, destSlot, depth)
        self.server.taskManager:registerTask(summary, task)
        if not skipDependencies then
            self:attachDependencies(task, recipe, depth, visiting, batch, summary)
            task.dependenciesPlanned = true
        end
        self.server.taskManager:addTask(task)
        remaining = remaining - batch
    end
end

function CraftPlanner:attachDependencies(task, recipe, depth, visiting, craftCount, summary)
    DependencyResolver.attachDependencies(self, task, recipe, depth, visiting, craftCount, summary)
end


function CraftPlanner:logMachineSummary()
    if not self.server or not self.server.taskManager or not self.server.craftRegistry then
        return
    end
    local stats = self.server.taskManager:getMachineStats()
    self.logger.info("[planner] machines:")
    for machineType, entry in pairs(stats) do
        local total = self.server.craftRegistry:countMachines(machineType)
        local available = self.server.craftRegistry:countAvailableMachines(machineType)
        self.logger.info(
            "  " .. machineType .. ":",
            tostring(available) .. " available,",
            tostring(total) .. " total,",
            tostring(entry.total) .. " tasks,",
            tostring(entry.waiting_machine) .. " waiting_machine,",
            tostring(entry.waiting_inputs) .. " waiting_inputs"
        )
    end
end

function CraftPlanner:setCriticalMachine()
    if not self.server or not self.server.taskManager or not self.server.craftRegistry then
        return
    end
    local stats = self.server.taskManager:getMachineStats()
    local critical = nil
    local criticalRatio = -1
    for machineType, entry in pairs(stats) do
        local count = self.server.craftRegistry:countMachines(machineType)
        if count > 0 then
            local ratio = entry.total / count
            if ratio > criticalRatio then
                criticalRatio = ratio
                critical = machineType
            end
        end
    end
    self.server.taskManager.currentCriticalMachine = critical
end

return CraftPlanner
