local Object = require 'object.Object'
local CraftTask = require 'inv.task.CraftTask'
local WaitTask = require 'inv.task.WaitTask'
local Log = require 'inv.Log'

-- Builds a dependency tree (DAG) of crafting tasks before execution.
local CraftPlanner = Object:subclass()

function CraftPlanner:init(server)
    self.server = server
    self.maxDepth = 32
end

local function criteriaKey(item)
    if item.name then
        return "name:" .. item.name
    end
    if item.tags then
        local keys = {}
        for tag, v in pairs(item.tags) do
            table.insert(keys, tag)
        end
        table.sort(keys)
        return "tags:" .. table.concat(keys, ",")
    end
    return "unknown"
end

local function findOutputCount(recipe, criteria)
    for slot, item in pairs(recipe.output) do
        if criteria:matches(item) then
            return item.count
        end
    end
    return 0
end

function CraftPlanner:plan(criteria, dest, destSlot)
    local recipe = self.server.craftRegistry:findRecipe(criteria)
    if not recipe then
        return 0
    end

    local nOut = findOutputCount(recipe, criteria)
    if nOut <= 0 then
        return 0
    end

    local crafts = math.ceil(criteria.count / nOut)
    Log.info("[planner] plan", crafts, "craft(s) on", recipe.machine, "at", string.format("%.2fs", os.clock()))
    local summary = self.server.taskManager:createSummary(criteria, crafts)
    self:queueTasks(recipe, crafts, summary, nil, dest, destSlot, 0, {})
    self:setCriticalMachine()
    self:logMachineSummary()
    return crafts
end

function CraftPlanner:queueTasks(recipe, crafts, summary, parent, dest, destSlot, depth, visiting)
    local machineCount = self.server.craftRegistry:countAvailableMachines(recipe.machine)
    local batches = crafts
    if machineCount > 0 then
        batches = math.min(crafts, machineCount)
    else
        batches = 1
    end
    local remaining = crafts
    for i = 1, batches do
        local batch = math.ceil(remaining / (batches - i + 1))
        local task = CraftTask(self.server, parent, recipe, dest, destSlot, batch, summary)
        self.server.taskManager:registerTask(summary, task)
        self:attachDependencies(task, recipe, depth, visiting, batch, summary)
        self.server.taskManager:addTask(task)
        remaining = remaining - batch
    end
end

local function scaledInputs(recipe, craftCount)
    local inputs = {}
    for _, item in pairs(recipe.input) do
        local copy = item:copy()
        copy.count = copy.count * craftCount
        table.insert(inputs, copy)
    end
    return inputs
end

function CraftPlanner:attachDependencies(task, recipe, depth, visiting, craftCount, summary)
    if depth > self.maxDepth then
        Log.warn("[planner] max depth exceeded for recipe", recipe.machine)
        return
    end

    local count = craftCount or 1
    local missing = self.server.inventoryIndex:tryMatchAll(scaledInputs(recipe, count))
    if #missing == 0 then
        return
    end

    for i, item in ipairs(missing) do
        local key = criteriaKey(item)
        if visiting[key] then
            Log.warn("[planner] cycle detected at", key)
            self.server.taskManager:addTask(WaitTask(self.server, task, item))
        else
            visiting[key] = true
            local depRecipe = self.server.craftRegistry:findRecipe(item)
            if depRecipe then
                local nOut = findOutputCount(depRecipe, item)
                if nOut > 0 then
                    local crafts = math.ceil(item.count / nOut)
                    self:queueTasks(depRecipe, crafts, summary, task, nil, nil, depth + 1, visiting)
                else
                    self.server.taskManager:addTask(WaitTask(self.server, task, item))
                end
            else
                self.server.taskManager:addTask(WaitTask(self.server, task, item))
            end
            visiting[key] = nil
        end
    end
end

function CraftPlanner:logMachineSummary()
    if not self.server or not self.server.taskManager or not self.server.craftRegistry then
        return
    end
    local stats = self.server.taskManager:getMachineStats()
    Log.info("[planner] machines:")
    for machineType, entry in pairs(stats) do
        local total = self.server.craftRegistry:countMachines(machineType)
        local available = self.server.craftRegistry:countAvailableMachines(machineType)
        Log.info(
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
