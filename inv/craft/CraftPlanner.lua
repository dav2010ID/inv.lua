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

    local compatibleCount = 0
    if self.server.machineRegistry then
        local machines = self.server.machineRegistry:getMachines(recipe.machine)
        if machines then
            for _, machine in pairs(machines) do
                if machine.canAcceptRecipe then
                    if machine:canAcceptRecipe(recipe) then
                        compatibleCount = compatibleCount + 1
                    end
                else
                    compatibleCount = compatibleCount + 1
                end
            end
        end
    end

    if compatibleCount == 0 then
        self.logger.warn("[planner] no machine compatible with recipe modifiers for", recipe.machine)
        return nil, "no_compatible_machine"
    end

    local crafts = math.ceil(criteria.count / nOut)
    self.logger.info("[planner] plan", crafts, "craft(s) on", recipe.machine, "(" .. compatibleCount .. " compatible) at",
        string.format("%.2fs", os.clock()))
    return { criteria = criteria, recipe = recipe, crafts = crafts }, nil
end

return CraftPlanner
