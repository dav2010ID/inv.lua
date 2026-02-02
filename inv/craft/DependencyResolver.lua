local WaitTask = require 'inv.task.WaitTask'

local DependencyResolver = {}

local function criteriaKey(item)
    if item.name then
        return "name:" .. item.name
    end
    if item.tags then
        local keys = {}
        for tag, _ in pairs(item.tags) do
            table.insert(keys, tag)
        end
        table.sort(keys)
        return "tags:" .. table.concat(keys, ",")
    end
    return "unknown"
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

function DependencyResolver.findOutputCount(recipe, criteria)
    for _, item in pairs(recipe.output) do
        if criteria:matches(item) then
            return item.count
        end
    end
    return 0
end

function DependencyResolver.attachDependencies(planner, task, recipe, depth, visiting, craftCount, summary)
    if depth > planner.maxDepth then
        planner.logger.warn("[planner] max depth exceeded for recipe", recipe.machine)
        return
    end

    local count = craftCount or 1
    local missing = planner.server.inventoryIndex:tryMatchAll(scaledInputs(recipe, count))
    if #missing == 0 then
        return
    end

    for _, item in ipairs(missing) do
        local key = criteriaKey(item)
        if visiting[key] then
            planner.logger.warn("[planner] cycle detected at", key)
            planner.server.taskManager:addTask(WaitTask(planner.server, task, item))
        else
            visiting[key] = true
            local depRecipe = planner.server.craftRegistry:findRecipe(item)
            if depRecipe then
                local nOut = DependencyResolver.findOutputCount(depRecipe, item)
                if nOut > 0 then
                    local crafts = math.ceil(item.count / nOut)
                    planner:queueTasks(depRecipe, crafts, summary, task, nil, nil, depth + 1, visiting, false)
                else
                    planner.server.taskManager:addTask(WaitTask(planner.server, task, item))
                end
            else
                planner.server.taskManager:addTask(WaitTask(planner.server, task, item))
            end
            visiting[key] = nil
        end
    end
end

return DependencyResolver
