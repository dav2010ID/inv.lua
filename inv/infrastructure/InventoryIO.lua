local Class = require 'inv.core.Class'

-- Handles IO operations against storage devices and updates the index.
local InventoryIO = Class:subclass()

function InventoryIO:init(server, index)
    self.server = server
    self.index = index
end

function InventoryIO:getStorageRegistry()
    assert(self.server.storageRegistry, "StorageRegistry not initialized")
    return self.server.storageRegistry
end

-- Scans all connected inventories, adding their stored items to the database.
-- Resets any preexisting item counts to 0 beforehand.
function InventoryIO:scanInventories()
    local oldCounts = {}
    for name, item in pairs(self.index.items) do
        oldCounts[name] = item.count
        item.count = 0
    end

    local storageRegistry = self:getStorageRegistry()
    for i, device in ipairs(storageRegistry.storage) do
        self:scanInventory(device, false)
    end

    for name, item in pairs(self.index.items) do
        if oldCounts[name] ~= item.count then
            self.index:markUpdated(name)
        end
    end
end

-- Scans a connected inventory and adds its stored items to the database.
function InventoryIO:scanInventory(device, markUpdates)
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
-- count and targetSlot are optional.
function InventoryIO:push(targetDevice, criteria, count, targetSlot)
    local moved = 0
    local matches = self.index:resolveCriteria(criteria)
    local targetCount = count or criteria.count or 0
    if targetCount <= 0 then
        return 0
    end

    local storageRegistry = self:getStorageRegistry()
    storageRegistry:ensureSorted()
    for i, device in ipairs(storageRegistry.storage) do
        local items = device:list()

        for slot, deviceItem in pairs(items) do
            if matches[deviceItem.name] then
                local toMove = math.min(deviceItem.count, targetCount - moved)
                local n = device:push(targetDevice, slot, toMove, targetSlot)

                if n > 0 then
                    moved = moved + n

                    local info = self.index.items[deviceItem.name]
                    info.count = info.count - n
                    self.index:markUpdated(deviceItem.name)
                end

                if moved >= targetCount then
                    return moved
                end
            end
        end
    end

    return moved
end

-- Attempts to pull a given amount of items into the system.
function InventoryIO:pull(sourceDevice, item, count, sourceSlot)
    local moved = 0
    self.index:updateDB(item) -- ensure we know what we're adding to the system
    local targetCount = count or item.count or 0
    if targetCount <= 0 then
        return 0
    end

    local storageRegistry = self:getStorageRegistry()
    storageRegistry:ensureSorted()
    for i, device in ipairs(storageRegistry.storage) do
        local toMove = targetCount - moved
        if device:itemAllowed(item) then
            local n = device:pull(sourceDevice, sourceSlot, toMove)
            moved = moved + n
            if moved >= targetCount then
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



