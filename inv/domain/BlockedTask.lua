local Task = require 'inv.domain.Task'

-- Represents a task blocked on missing items with no known recipe.
local BlockedTask = Task:subclass()

function BlockedTask:init(server, parent, item)
    BlockedTask.superClass.init(self, server, parent)
    -- The Item this task is waiting for.
    self.item = item
end

function BlockedTask:print()
    local parts = {"[task] waiting on items"}
    if self.item.name then
        table.insert(parts, self.item.name)
    elseif self.item.tags then
        for k, _ in pairs(self.item.tags) do
            table.insert(parts, k)
        end
    end
    self.server.logger.cli(table.concat(parts, " "))
end

function BlockedTask:run()
    if #self.server.inventoryService:tryMatchAll({self.item}) == 0 then
        return true
    end
    self.server.taskScheduler:recordWaitProgress(self)
    self.server.taskScheduler:setStatus(self, "blocked", "inputs")
    self:print()
    return false
end

return BlockedTask
