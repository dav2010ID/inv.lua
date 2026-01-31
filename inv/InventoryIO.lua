local Object = require 'object.Object'

-- Handles IO operations against storage devices and updates the index.
local InventoryIO = Object:subclass()

function InventoryIO:init(server, index)
    self.server = server
    self.index = index
end

function InventoryIO:getStorageManager()
    assert(self.server.storageManager, "StorageManager not initialized")
    return self.server.storageManager
end

-- Scans all connected inventories, adding their stored items to the database.
-- Resets any preexisting item counts to 0 beforehand.
function InventoryIO:scanInventories()
    for k, v in pairs(self.index.items) do
        v.count = 0
    end

    local storageManager = self:getStorageManager()
    for i, device in ipairs(storageManager.storage) do
        self:scanInventory(device)
    end
end

-- Scans a connected inventory and adds its stored items to the database.
function InventoryIO:scanInventory(device)
    local items = device:list()

    for slot, item in pairs(items) do
        local entry = self.index.items[item.name]
        if not entry or not entry.detailed then
            local detail = device:getItemDetail(slot)
            self.index:updateDB(detail)
        end
        self.index.items[item.name].count = self.index.items[item.name].count + item.count
    end
end

-- Attempts to push a given amount of items out from the system.
-- destSlot is optional.
function InventoryIO:pushItemsTo(criteria, destDevice, destSlot)
    local moved = 0
    local matches = self.index:resolveCriteria(criteria)

    local storageManager = self:getStorageManager()
    storageManager:ensureSorted()
    for i, device in ipairs(storageManager.storage) do
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
function InventoryIO:pullItemsFrom(item, srcDevice, srcSlot)
    local moved = 0
    self.index:updateDB(item) -- ensure we know what we're adding to the system

    local storageManager = self:getStorageManager()
    storageManager:ensureSorted()
    for i, device in ipairs(storageManager.storage) do
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

return InventoryIO
