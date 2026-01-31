local Task = require 'inv.task.Task'
local CraftTask = require 'inv.task.CraftTask'
local WaitTask = require 'inv.task.WaitTask'

-- Fetches or crafts items from the network.
local FetchTask = Task:subclass()

function FetchTask:init(server, parent, criteria, dest, destSlot)
    FetchTask.superClass.init(self, server, parent)
    self.criteria = criteria
    self.dest = dest
    self.destSlot = destSlot
    self.moved = 0
    self.enqueued = false
end

function FetchTask:run()
    if self.moved < self.criteria.count then
        local remaining = self.criteria:copy()
        remaining.count = self.criteria.count - self.moved
        self.moved = self.moved + self.server.inventoryIO:pushItemsTo(remaining, self.dest, self.destSlot)
    end

    if self.moved >= self.criteria.count then
        return true
    end

    if not self.enqueued then
        self.enqueued = true
        local remaining = self.criteria:copy()
        remaining.count = self.criteria.count - self.moved
        local recipe = self.server.craftRegistry:findRecipe(remaining)
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
                    self.server.taskManager:addTask(CraftTask(self.server, self, recipe, self.dest, self.destSlot))
                end
            else
                self.server.taskManager:addTask(WaitTask(self.server, self, remaining))
            end
        else
            self.server.taskManager:addTask(WaitTask(self.server, self, remaining))
        end
    end

    return false
end

return FetchTask
