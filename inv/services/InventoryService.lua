local Class = require 'inv.core.Class'
local InventoryIndex = require 'inv.services.InventoryIndex'
local InventoryIO = require 'inv.infrastructure.InventoryIO'

local InventoryQuery = Class:subclass()
local InventoryMutator = Class:subclass()

function InventoryQuery:init(server, index)
    self.server = server
    self.index = index
end

function InventoryQuery:getItems()
    return self.index.items
end

function InventoryQuery:getItem(name)
    return self.index.items[name]
end

function InventoryQuery:getItemCount(name)
    local item = self.index.items[name]
    return item and item.count or 0
end

function InventoryQuery:resolveCriteria(criteria)
    return self.index:resolveCriteria(criteria)
end

function InventoryQuery:tryMatchAll(items)
    return self.index:tryMatchAll(items)
end

function InventoryMutator:init(server, index)
    self.server = server
    self.index = index
    self.transfer = InventoryIO(server, self.index)
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
function InventoryMutator:push(target, item, count, targetSlot)
    local criteria = normalizeCriteria(item, count)
    return self.transfer:push(target, criteria, criteria.count, targetSlot)
end

-- Pulls items from a source device into storage.
-- count and sourceSlot are optional (falls back to item.count if omitted).
function InventoryMutator:pull(source, item, count, sourceSlot)
    local criteria = normalizeCriteria(item, count)
    return self.transfer:pull(source, criteria, criteria.count, sourceSlot)
end

function InventoryMutator:scanInventories()
    return self.transfer:scanInventories()
end

function InventoryMutator:scanInventory(device, markUpdates)
    return self.transfer:scanInventory(device, markUpdates)
end

function InventoryMutator:addItem(name)
    return self.index:addItem(name)
end

function InventoryMutator:updateTags(name)
    return self.index:updateTags(name)
end

function InventoryMutator:updateDB(detail)
    return self.index:updateDB(detail)
end

function InventoryMutator:markUpdated(name)
    return self.index:markUpdated(name)
end

function InventoryMutator:getUpdatedItems()
    return self.index:getUpdatedItems()
end

return {
    InventoryIndex = InventoryIndex,
    InventoryQuery = InventoryQuery,
    InventoryMutator = InventoryMutator
}



