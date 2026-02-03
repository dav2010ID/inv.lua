local Class = require 'inv.core.Class'
local Table = require 'inv.infrastructure.util.Table'

-- Manages storage devices and their ordering.
local StorageRegistry = Class:subclass()

function StorageRegistry:init(server)
    self.server = server
    -- table<int, Storage>: The inventories connected to this network.
    self.storage = {}
    -- bool: Whether the storage list is currently sorted.
    self.sorted = false
end

-- Adds an inventory to the network, updating network state as necessary.
function StorageRegistry:addStorage(device)
    table.insert(self.storage, device)
    self.sorted = false
    if self.server.inventoryMutator then
        self.server.inventoryMutator:scanInventory(device)
    end
end

-- Removes an inventory from the network, updating network state as necessary.
function StorageRegistry:removeStorage(device)
    Table.removeItem(self.storage, device)
    self.sorted = false
    if self.server.inventoryMutator then
        self.server.inventoryMutator:scanInventories()
    end
end

-- Static comparison method.
-- Returns true if inventory a should be sorted before inventory b.
function StorageRegistry.deviceSort(a, b)
    if a.priority ~= b.priority then
        return a.priority > b.priority
    end
    return a.name < b.name
end

-- Sorts the list of connected inventories if necessary.
function StorageRegistry:ensureSorted()
    if not self.sorted then
        table.sort(self.storage, self.deviceSort)
        self.sorted = true
    end
end

-- Returns a shallow copy of the storage list.
function StorageRegistry:list()
    return Table.copyShallow(self.storage)
end

return StorageRegistry



