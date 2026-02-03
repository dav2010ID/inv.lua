local CraftGraph = {}

local function identityKey(ctx, item)
    if ctx and ctx.identityKey then
        return ctx.identityKey(item)
    end
    if item and item.identityKey then
        return item:identityKey()
    end
    return tostring(item)
end

local function scaledInputs(recipe, craftCount)
    return recipe:scaledInputs(craftCount)
end

local function addWait(ctx, task, item, summaryId, reason, result)
    if ctx and ctx.addWait then
        ctx.addWait(task, item, summaryId, reason)
    end
    result.blocked = result.blocked + 1
end

local function enqueue(ctx, task, recipe, crafts, depth, visiting, summaryId, result)
    if ctx and ctx.enqueueRecipe then
        ctx.enqueueRecipe(task, recipe, crafts, depth, visiting, summaryId)
    end
    result.added = result.added + 1
end

function CraftGraph.countProduced(recipe, criteria)
    return recipe:countProduced(criteria)
end

function CraftGraph.link(ctx, task, recipe, depth, visiting, craftCount, summaryId)
    local result = {added=0, blocked=0}
    local maxDepth = ctx and ctx.maxDepth or 0
    local count = craftCount or 1
    local logger = ctx and ctx.logger or nil

    if depth > maxDepth then
        if logger then
            logger.warn("[planner] max depth exceeded for recipe", recipe.machine)
        end
        local missing = ctx.inventoryQuery:tryMatchAll(scaledInputs(recipe, count))
        for _, item in ipairs(missing) do
            addWait(ctx, task, item, summaryId, "depth_limit", result)
        end
        return result
    end

    local missing = ctx.inventoryQuery:tryMatchAll(scaledInputs(recipe, count))
    if #missing == 0 then
        return result
    end

    for _, item in ipairs(missing) do
        local key = identityKey(ctx, item)
        if visiting[key] then
            if logger then
                logger.warn("[planner] cycle detected at", key)
            end
            addWait(ctx, task, item, summaryId, "cycle", result)
        else
            assert(visiting[key] == nil, "visiting key already set")
            visiting[key] = true
            local depRecipe = ctx.recipeStore:findRecipe(item)
            if depRecipe then
                local nOut = depRecipe:countProduced(item)
                if nOut > 0 then
                    local crafts = math.ceil(item.count / nOut)
                    enqueue(ctx, task, depRecipe, crafts, depth + 1, visiting, summaryId, result)
                else
                    addWait(ctx, task, item, summaryId, "invalid_output", result)
                end
            else
                addWait(ctx, task, item, summaryId, "no_recipe", result)
            end
            assert(visiting[key] == true, "visiting key corrupted")
            visiting[key] = nil
        end
    end
    return result
end

return CraftGraph
