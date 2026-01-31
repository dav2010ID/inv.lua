local Item = require 'inv.Item'

local RPCMethods = {}

local function isPositiveNumber(n)
    return type(n) == "number" and n > 0
end

function RPCMethods.listItems(server, clientID, refresh)
    if refresh == true then
        server.invManager:scanInventories()
    end
    local items = {}
    for k, item in pairs(server.invManager.items) do
        items[k] = item:serialize()
    end
    server:send(clientID, {"items",items})
end

function RPCMethods.requestItem(server, clientID, clientName, itemName, count)
    local device = server.deviceManager.devices[clientName]
    if not device then
        print("[rpc] requestItem: unknown client device " .. tostring(clientName))
        return
    end
    local n = tonumber(count) or 0
    if not isPositiveNumber(n) then
        print("[rpc] requestItem: invalid count " .. tostring(count))
        return
    end
    if not itemName then
        print("[rpc] requestItem: missing item name")
        return
    end
    local crit = Item{name=itemName, count=n}
    server.craftManager:pushOrCraftItemsTo(crit, device)
end

function RPCMethods.storeItems(server, clientID, clientName, items)
    local device = server.deviceManager.devices[clientName]
    if not device then
        print("[rpc] storeItems: unknown client device " .. tostring(clientName))
        return
    end
    if type(items) ~= "table" then
        print("[rpc] storeItems: invalid items payload")
        return
    end
    for slot, item in pairs(items) do
        if item and item.name and item.count then
            server.invManager:pullItemsFrom(item, device, slot)
        end
    end
end

function RPCMethods.unregister(server, clientID)
    server:unregister(clientID)
end

return RPCMethods
