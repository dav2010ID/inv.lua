local Device = require 'inv.device.Device'
local Item = require 'inv.Item'

-- Represents an inventory connected to the network.
local Storage = Device:subclass()

function Storage:init(server, name, deviceType, config)
    Storage.superClass.init(self, server, name, deviceType, config)
    self.priority = self.config.priority or 0

    self.filters = nil
    if self.config.filters then
        self.filters = {}
        for i, filter in ipairs(self.config.filters) do
            table.insert(self.filters, Item(filter))
        end
    end

    self.server.storageManager:addStorage(self)
end

function Storage:destroy()
    self.server.storageManager:removeStorage(self)
end

-- Returns true if the item can be stored in this Storage according to
-- this device's configured item filters.
function Storage:itemAllowed(item)
    if self.filters then
        for i,filter in ipairs(self.filters) do
            if filter:matches(item) then
                return true
            end
        end
        return false
    end
    return true
end

return Storage
