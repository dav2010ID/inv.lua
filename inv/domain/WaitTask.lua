local Task = require 'inv.domain.Task'

-- Waits for a missing item that has no known recipe.
local WaitTask = Task:subclass()

function WaitTask:init(server, parent, item)
    WaitTask.superClass.init(self, server, parent)
    self.item = item
end

local function itemKey(item)
    if item.name then
        return item.name
    end
    if item.tags then
        for tag, _ in pairs(item.tags) do
            return "tag:" .. tag
        end
    end
    return nil
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
    if #self.server.inventoryQuery:tryMatchAll({self.item}) == 0 then
        return true
    end
    self.server.taskScheduler:recordWaitProgress(self)
    self.server.taskScheduler:setStatus(self, "blocked", "inputs", itemKey(self.item))
    self:print()
    return false
end

return WaitTask
