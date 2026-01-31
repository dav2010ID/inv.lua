local Object = require 'object.Object'
local Common = require 'inv.Common'

-- Manages storage devices and their ordering.
local StorageManager = Object:subclass()

function StorageManager:init(server)
    self.server = server
    -- table<int, Storage>: The inventories connected to this network.
    self.storage = {}
    -- bool: Whether the storage list is currently sorted.
    self.sorted = false
end

-- Adds an inventory to the network, updating network state as necessary.
function StorageManager:addStorage(device)
    table.insert(self.storage, device)
    self.sorted = false
    if self.server.inventoryIO then
        self.server.inventoryIO:scanInventory(device)
    end
end

-- Removes an inventory from the network, updating network state as necessary.
function StorageManager:removeStorage(device)
    Common.removeItem(self.storage, device)
    self.sorted = false
    if self.server.inventoryIO then
        self.server.inventoryIO:scanInventories()
    end
end

-- Static comparison method.
-- Returns true if inventory a should be sorted before inventory b.
function StorageManager.deviceSort(a, b)
    if a.priority ~= b.priority then
        return a.priority > b.priority
    end
    return a.name < b.name
end

-- Sorts the list of connected inventories if necessary.
function StorageManager:ensureSorted()
    if not self.sorted then
        table.sort(self.storage, self.deviceSort)
        self.sorted = true
    end
end

return StorageManager
