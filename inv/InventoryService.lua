local Object = require 'object.Object'
local InventoryIndex = require 'inv.InventoryIndex'
local InventoryTransfer = require 'inv.InventoryTransfer'

-- Facade for inventory index and transfer logic.
local InventoryService = Object:subclass()

function InventoryService:init(server)
    self.server = server
    self.index = InventoryIndex(server)
    self.transfer = InventoryTransfer(server, self.index)
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

function InventoryService:pushItemsTo(criteria, dest, destSlot)
    return self.transfer:pushItemsTo(criteria, dest, destSlot)
end

function InventoryService:pullItemsFrom(item, src, srcSlot)
    return self.transfer:pullItemsFrom(item, src, srcSlot)
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
