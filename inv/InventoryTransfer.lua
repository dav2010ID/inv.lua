local Object = require 'object.Object'

-- Handles IO operations against storage devices and updates the index.
local InventoryTransfer = Object:subclass()

function InventoryTransfer:init(server, index)
    self.server = server
    self.index = index
end

function InventoryTransfer:getStoragePool()
    assert(self.server.storagePool, "StoragePool not initialized")
    return self.server.storagePool
end

-- Scans all connected inventories, adding their stored items to the database.
-- Resets any preexisting item counts to 0 beforehand.
function InventoryTransfer:scanInventories()
    local oldCounts = {}
    for name, item in pairs(self.index.items) do
        oldCounts[name] = item.count
        item.count = 0
    end

    local storagePool = self:getStoragePool()
    for i, device in ipairs(storagePool.storage) do
        self:scanInventory(device, false)
    end

    for name, item in pairs(self.index.items) do
        if oldCounts[name] ~= item.count then
            self.index:markUpdated(name)
        end
    end
end

-- Scans a connected inventory and adds its stored items to the database.
function InventoryTransfer:scanInventory(device, markUpdates)
    if markUpdates == nil then
        markUpdates = true
    end
    local items = device:list()

    for slot, item in pairs(items) do
        local entry = self.index.items[item.name]
        if not entry then
            entry = self.index:addItem(item.name)
        end
        if not entry.detailed then
            local detail = device:getItemDetail(slot)
            if detail then
                self.index:updateDB(detail)
                entry = self.index.items[item.name] or entry
            end
        end
        entry.count = entry.count + item.count
        if markUpdates then
            self.index:markUpdated(item.name)
        end
    end
end

-- Attempts to push a given amount of items out from the system.
-- destSlot is optional.
function InventoryTransfer:pushItemsTo(criteria, destDevice, destSlot)
    local moved = 0
    local matches = self.index:resolveCriteria(criteria)

    local storagePool = self:getStoragePool()
    storagePool:ensureSorted()
    for i, device in ipairs(storagePool.storage) do
        local items = device:list()

        for slot, deviceItem in pairs(items) do
            if matches[deviceItem.name] then
                local toMove = math.min(deviceItem.count, criteria.count - moved)
                local n = device:pushItems(destDevice, slot, toMove, destSlot)

                if n > 0 then
                    moved = moved + n

                    local info = self.index.items[deviceItem.name]
                    info.count = info.count - n
                    self.index:markUpdated(deviceItem.name)
                end

                if moved >= criteria.count then
                    return moved
                end
            end
        end
    end

    return moved
end

-- Attempts to pull a given amount of items into the system.
function InventoryTransfer:pullItemsFrom(item, srcDevice, srcSlot)
    local moved = 0
    self.index:updateDB(item) -- ensure we know what we're adding to the system

    local storagePool = self:getStoragePool()
    storagePool:ensureSorted()
    for i, device in ipairs(storagePool.storage) do
        local toMove = item.count - moved
        if device:itemAllowed(item) then
            local n = device:pullItems(srcDevice, srcSlot, toMove)
            moved = moved + n
            if moved >= item.count then
                break
            end
        end
    end

    if moved > 0 then
        local info = self.index.items[item.name]
        info.count = info.count + moved

        self.index:markUpdated(item.name)
    end

    return moved
end

return InventoryTransfer
