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
    local planned = 0
    for i=1,crafts do
        local task = CraftTask(self.server, nil, recipe, dest, destSlot)
        self:attachDependencies(task, recipe, 0, {})
        self.server.taskManager:addTask(task)
        planned = planned + 1
    end
    return planned
end

function CraftPlanner:attachDependencies(task, recipe, depth, visiting)
    if depth > self.maxDepth then
        Log.warn("[planner] max depth exceeded for recipe", recipe.machine)
        return
    end

    local missing = self.server.inventoryIndex:tryMatchAll(recipe.input)
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
                    for j=1,crafts do
                        local child = CraftTask(self.server, task, depRecipe)
                        self:attachDependencies(child, depRecipe, depth + 1, visiting)
                        self.server.taskManager:addTask(child)
                    end
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

return CraftPlanner
