local Task = require 'inv.task.Task'

-- Waits for a missing item that has no known recipe.
local WaitTask = Task:subclass()

function WaitTask:init(server, parent, item)
    WaitTask.superClass.init(self, server, parent)
    -- The Item this task is waiting for.
    self.item = item
end

function WaitTask:print()
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

function WaitTask:run()
    if #self.server.inventoryIndex:tryMatchAll({self.item}) == 0 then
        return true
    end
    self:print()
    return false
end

return WaitTask
