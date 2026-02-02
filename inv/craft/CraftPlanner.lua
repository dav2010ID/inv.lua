local Object = require 'inv.core.Object'
local CraftDependencyGraph = require 'inv.craft.CraftDependencyGraph'

-- Builds a dependency tree (DAG) of crafting tasks before execution.
local CraftPlanner = Object:subclass()

function CraftPlanner:init(server)
    self.server = server
    self.logger = server.logger
end

function CraftPlanner:plan(criteria)
    local recipe = self.server.recipeStore:findRecipe(criteria)
    if not recipe then
        return nil
    end

    local nOut = CraftDependencyGraph.findOutputCount(recipe, criteria)
    if nOut <= 0 then
        return nil
    end

    local crafts = math.ceil(criteria.count / nOut)
    self.logger.info("[planner] plan", crafts, "craft(s) on", recipe.machine, "at", string.format("%.2fs", os.clock()))
    return {criteria = criteria, recipe = recipe, crafts = crafts}
end

return CraftPlanner

