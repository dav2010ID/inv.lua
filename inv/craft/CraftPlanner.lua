local Class = require 'inv.core.Class'
local CraftGraph = require 'inv.domain.CraftGraph'

-- Builds a dependency tree (DAG) of crafting tasks before execution.
local CraftPlanner = Class:subclass()

function CraftPlanner:init(server)
    self.server = server
    self.logger = server.logger
end

function CraftPlanner:plan(criteria)
    local plan = self:planWithReason(criteria)
    return plan
end

function CraftPlanner:planWithReason(criteria)
    local recipe = self.server.recipeStore:findRecipe(criteria)
    if not recipe then
        return nil, "no_recipe"
    end

    local nOut = recipe:countProduced(criteria)
    if nOut <= 0 then
        return nil, "invalid_output"
    end

    local crafts = math.ceil(criteria.count / nOut)
    self.logger.info("[planner] plan", crafts, "craft(s) on", recipe.machine, "at", string.format("%.2fs", os.clock()))
    return {criteria = criteria, recipe = recipe, crafts = crafts}, nil
end

return CraftPlanner



