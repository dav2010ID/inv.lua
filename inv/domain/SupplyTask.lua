local Task = require 'inv.domain.Task'
local CraftTask = require 'inv.domain.CraftTask'
local BlockedTask = require 'inv.domain.BlockedTask'

-- Fetches or crafts items from the network.
local SupplyTask = Task:subclass()

function SupplyTask:init(server, parent, criteria, dest, destSlot)
    SupplyTask.superClass.init(self, server, parent)
    self.criteria = criteria
    self.dest = dest
    self.destSlot = destSlot
    self.moved = 0
    self.enqueued = false
end

function SupplyTask:run()
    if self.moved < self.criteria.count then
        local remaining = self.criteria:copy()
        remaining.count = self.criteria.count - self.moved
        self.moved = self.moved + self.server.inventoryService:push(self.dest, remaining, remaining.count, self.destSlot)
    end

    if self.moved >= self.criteria.count then
        return true
    end

    if not self.enqueued then
        self.enqueued = true
        local remaining = self.criteria:copy()
        remaining.count = self.criteria.count - self.moved
        local recipe = self.server.recipeStore:findRecipe(remaining)
        if recipe then
            local nOut = 0
            for slot, item in pairs(recipe.output) do
                if remaining:matches(item) then
                    nOut = item.count
                    break
                end
            end
            if nOut > 0 then
                local toMake = remaining.count
                local crafts = math.ceil(toMake / nOut)
                for i=1,crafts do
                    self.server.taskScheduler:addTask(CraftTask(self.server, self, recipe, self.dest, self.destSlot, 1, nil, 0))
                end
            else
                self.server.taskScheduler:addTask(BlockedTask(self.server, self, remaining))
            end
        else
            self.server.taskScheduler:addTask(BlockedTask(self.server, self, remaining))
        end
    end

    return false
end

return SupplyTask
