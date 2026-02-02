local Object = require 'object.Object'
local DependencyResolver = require 'inv.craft.DependencyResolver'

-- Builds a dependency tree (DAG) of crafting tasks before execution.
local CraftPlanner = Object:subclass()

function CraftPlanner:init(server)
    self.server = server
    self.logger = server.logger
    self.maxDepth = 32
end

function CraftPlanner:plan(criteria, dest, destSlot)
    local recipe = self.server.recipeStore:findRecipe(criteria)
    if not recipe then
        return 0
    end

    local nOut = DependencyResolver.findOutputCount(recipe, criteria)
    if nOut <= 0 then
        return 0
    end

    local crafts = math.ceil(criteria.count / nOut)
    self.logger.info("[planner] plan", crafts, "craft(s) on", recipe.machine, "at", string.format("%.2fs", os.clock()))
    local summary = self.server.taskScheduler:createSummary(criteria, crafts)
    self.server.taskScheduler:queueTasks(self, recipe, crafts, summary, nil, dest, destSlot, 0, {}, false)
    self.server.machineScheduler:setCriticalMachine()
    self.server.machineScheduler:logMachineSummary()
    return crafts
end

function CraftPlanner:attachDependencies(task, recipe, depth, visiting, craftCount, summary)
    DependencyResolver.attachDependencies(self, task, recipe, depth, visiting, craftCount, summary)
end


return CraftPlanner
