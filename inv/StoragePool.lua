local Object = require 'object.Object'
local Table = require 'inv.util.Table'

-- Manages storage devices and their ordering.
local StoragePool = Object:subclass()

function StoragePool:init(server)
    self.server = server
    -- table<int, Storage>: The inventories connected to this network.
    self.storage = {}
    -- bool: Whether the storage list is currently sorted.
    self.sorted = false
end

-- Adds an inventory to the network, updating network state as necessary.
function StoragePool:addStorage(device)
    table.insert(self.storage, device)
    self.sorted = false
    if self.server.inventoryService then
        self.server.inventoryService:scanInventory(device)
    end
end

-- Removes an inventory from the network, updating network state as necessary.
function StoragePool:removeStorage(device)
    Table.removeItem(self.storage, device)
    self.sorted = false
    if self.server.inventoryService then
        self.server.inventoryService:scanInventories()
    end
end

-- Static comparison method.
-- Returns true if inventory a should be sorted before inventory b.
function StoragePool.deviceSort(a, b)
    if a.priority ~= b.priority then
        return a.priority > b.priority
    end
    return a.name < b.name
end

-- Sorts the list of connected inventories if necessary.
function StoragePool:ensureSorted()
    if not self.sorted then
        table.sort(self.storage, self.deviceSort)
        self.sorted = true
    end
end

return StoragePool
