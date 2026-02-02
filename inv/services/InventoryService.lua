local Object = require 'object.Object'
local InventoryIndex = require 'inv.services.InventoryIndex'
local InventoryIO = require 'inv.infrastructure.InventoryIO'

-- Facade for inventory index and transfer logic.
local InventoryService = Object:subclass()

function InventoryService:init(server)
    self.server = server
    self.index = InventoryIndex(server)
    self.transfer = InventoryIO(server, self.index)
end

function InventoryService:getItems()
    return self.index.items
end

function InventoryService:getItem(name)
    return self.index.items[name]
end

function InventoryService:getItemCount(name)
    local item = self.index.items[name]
    return item and item.count or 0
end

function InventoryService:scanInventories()
    return self.transfer:scanInventories()
end

function InventoryService:scanInventory(device, markUpdates)
    return self.transfer:scanInventory(device, markUpdates)
end

local function normalizeCriteria(criteria, count)
    if count == nil then
        return criteria
    end
    local copy = criteria.copy and criteria:copy() or {name = criteria.name, tags = criteria.tags}
    copy.count = count
    return copy
end

-- Pushes items from storage to a target device.
-- count and targetSlot are optional (falls back to item.count if omitted).
function InventoryService:push(target, item, count, targetSlot)
    local criteria = normalizeCriteria(item, count)
    return self.transfer:push(target, criteria, criteria.count, targetSlot)
end

-- Pulls items from a source device into storage.
-- count and sourceSlot are optional (falls back to item.count if omitted).
function InventoryService:pull(source, item, count, sourceSlot)
    local criteria = normalizeCriteria(item, count)
    return self.transfer:pull(source, criteria, criteria.count, sourceSlot)
end

function InventoryService:resolveCriteria(criteria)
    return self.index:resolveCriteria(criteria)
end

function InventoryService:tryMatchAll(items)
    return self.index:tryMatchAll(items)
end

function InventoryService:addItem(name)
    return self.index:addItem(name)
end

function InventoryService:updateTags(name)
    return self.index:updateTags(name)
end

function InventoryService:updateDB(detail)
    return self.index:updateDB(detail)
end

function InventoryService:markUpdated(name)
    return self.index:markUpdated(name)
end

function InventoryService:getUpdatedItems()
    return self.index:getUpdatedItems()
end

return InventoryService
