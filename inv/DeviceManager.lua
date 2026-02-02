local Object = require 'object.Object'

local Common = require 'inv.Common'
local Storage = require 'inv.device.Storage'
local Machine = require 'inv.device.Machine'
local Log = require 'inv.Log'

-- Manages network-attached devices, including storage and crafting machines.
-- Specialized behavior is delegated by Devices to the appropriate class
-- (either InventoryIO or CraftRegistry).
local DeviceManager = Object:subclass()

function DeviceManager:init(server, overrides)
    self.server = server
    -- table<string, Device>: Devices connected to this network.
    self.devices = {}

    -- table<string, table>: Configuration applied to specific device types.
    self.typeOverrides = {}
    -- table<string, table>: Configuration applied to individual devices by name.
    self.nameOverrides = {}

    for i,v in ipairs(overrides) do
        if v.type then
            self.typeOverrides[v.type] = v
        elseif v.name then
            self.nameOverrides[v.name] = v
        end
    end
end

-- Scans and adds all devices connected to the network.
-- Clears any existing loaded devices beforehand.
function DeviceManager:scanDevices()
    for name,device in pairs(self.devices) do
        device:destroy()
    end
    self.devices = {}

    for i,name in ipairs(peripheral.getNames()) do
        self:addDevice(name)
    end
end

-- Copies configuration entries to the given table.
-- Preexisting entries of the same name are overwritten.
function DeviceManager:copyConfig(entries, dest)
    if entries then
        for k,v in pairs(entries) do
            dest[k] = v
        end
    end
end

-- Gets all configuration for the given device name and type.
-- Device type settings are overridden by name-specific settings.
function DeviceManager:getConfig(name, deviceType)
    local config = {}
    self:copyConfig(self.typeOverrides[deviceType], config)
    self:copyConfig(self.nameOverrides[name], config)
    return config
end

-- Creates the appropriate Device for the given network peripheral
-- as specified in the server configuration.
function DeviceManager:createDevice(name)
    assert(name ~= Common.getNameLocal())

    local types = { peripheral.getType(name) }
    local deviceType = nil
    local genericTypes = {}

    for k,v in pairs(types) do
        if v == "inventory" or v == "fluid_storage" or v == "energy_storage" then
            genericTypes[v] = true
        else
            deviceType = v
        end
    end

    local config = self:getConfig(name, deviceType)
    if deviceType == "workbench" then
        if config.purpose == nil then
            config.purpose = "crafting"
        end
        if config.backend == nil then
            config.backend = "turtle"
        end
        if config.slots == nil then
            config.slots = {
                [1]=1,  [2]=2,  [3]=3,
                [4]=5,  [5]=6,  [6]=7,
                [7]=9,  [8]=10, [9]=11,
                [10]=16
            }
        end
        if config.craftOutputSlot == nil then
            config.craftOutputSlot = 10
        end
    end

    if config.purpose == "crafting" and not deviceType then
        deviceType = config.machineType or config.type
    end

    if config.purpose == "crafting" then
        if not deviceType then
            Log.warn("[device] crafting device missing type", name)
            return nil
        end
        local machine = Machine(self.server, name, deviceType, config)
        Log.info("[device] machine attached", name, "type", deviceType)
        return machine
    elseif config.purpose == "storage" or genericTypes["inventory"] then
        local storage = Storage(self.server, name, deviceType, config)
        Log.info("[device] storage attached", name, "type", deviceType or "inventory")
        return storage
    end

    if deviceType then
        Log.warn("[device] unconfigured device", name, "type", deviceType)
    else
        Log.warn("[device] unconfigured device", name, "(unknown type)")
    end
    return nil
end

-- Creates the appropriate Device for the given network peripheral,
-- then adds it to the device table.
function DeviceManager:addDevice(name)
    if self.devices[name] then
        Log.info("[device] skipped double add device", name)
        --self.devices[name]:destroy()
        return
    end
    Log.info("[device] attach event", name)
    self.devices[name] = self:createDevice(name)
end

-- Removes a device from the device table, clearing any associated state.
function DeviceManager:removeDevice(name)
    local device = self.devices[name]
    if device then
        Log.info("[device] detach event", name, "type", device.type or "unknown")
        self.devices[name] = nil
        device:destroy()
    else
        Log.warn("[device] double remove device", name)
    end
end

return DeviceManager
