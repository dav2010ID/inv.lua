local CraftGraph = {}

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

function CraftGraph.countProduced(recipe, criteria)
    for _, item in pairs(recipe.output) do
        if criteria:matches(item) then
            return item.count
        end
    end
    return 0
end

function CraftGraph.link(builder, task, recipe, depth, visiting, craftCount, summaryId)
    if depth > builder.maxDepth then
        builder.logger.warn("[planner] max depth exceeded for recipe", recipe.machine)
        return
    end

    local count = craftCount or 1
    local missing = builder.server.inventoryQuery:tryMatchAll(scaledInputs(recipe, count))
    if #missing == 0 then
        return
    end

    for _, item in ipairs(missing) do
        local key = criteriaKey(item)
        if visiting[key] then
            builder.logger.warn("[planner] cycle detected at", key)
            builder:addWaitTask(task, item, summaryId)
        else
            visiting[key] = true
            local depRecipe = builder.server.recipeStore:findRecipe(item)
            if depRecipe then
                local nOut = CraftGraph.countProduced(depRecipe, item)
                if nOut > 0 then
                    local crafts = math.ceil(item.count / nOut)
                    builder.queue:enqueueRecipe(depRecipe, crafts, summaryId, task, nil, nil, depth + 1, visiting, false)
                else
                    builder:addWaitTask(task, item, summaryId)
                end
            else
                builder:addWaitTask(task, item, summaryId)
            end
            visiting[key] = nil
        end
    end
end

return CraftGraph
