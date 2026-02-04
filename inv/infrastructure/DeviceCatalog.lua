local Class = require 'inv.core.Class'

local Net = require 'inv.infrastructure.util.Net'
local Storage = require 'inv.infrastructure.device.Storage'
local Machine = require 'inv.infrastructure.device.Machine'
local GtceuMachine = require 'inv.infrastructure.device.GtceuMachine'
local BackendRegistry = require 'inv.infrastructure.machine.BackendRegistry'
local Log = require 'inv.infrastructure.Log'

-- Manages network-attached devices, including storage and crafting machines.
-- Specialized behavior is delegated by Devices to the appropriate class
-- (either InventoryIO or MachineScheduler).
local DeviceCatalog = Class:subclass()

local function resolveMachineClass(deviceType, config)
    if config and config.machineClass == "gtceu" then
        return GtceuMachine
    end
    if deviceType and string.find(deviceType, "^gtceu:") then
        return GtceuMachine
    end
    return Machine
end

function DeviceCatalog:init(server, overrides)
    self.server = server
    self.logger = server.logger
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
function DeviceCatalog:scanDevices()
    for name,device in pairs(self.devices) do
        device:destroy()
    end
    self.devices = {}

    for i,name in ipairs(peripheral.getNames()) do
        self:addDevice(name)
    end
end

-- Alias for scanDevices (new naming)
function DeviceCatalog:discoverDevices()
    return self:scanDevices()
end

-- Copies configuration entries to the given table.
-- Preexisting entries of the same name are overwritten.
function DeviceCatalog:copyConfig(entries, dest)
    if entries then
        for k,v in pairs(entries) do
            dest[k] = v
        end
    end
end

-- Gets all configuration for the given device name and type.
-- Device type settings are overridden by name-specific settings.
function DeviceCatalog:getConfig(name, deviceType)
    local config = {}
    self:copyConfig(self.typeOverrides[deviceType], config)
    self:copyConfig(self.nameOverrides[name], config)
    return config
end

-- Creates the appropriate Device for the given network peripheral
-- as specified in the server configuration.
function DeviceCatalog:createDevice(name)
    assert(name ~= Net.getNameLocal())

    local types = { peripheral.getType(name) }
    local deviceType = nil

    for k,v in pairs(types) do
        if v == "inventory" or v == "fluid_storage" or v == "energy_storage" then
            -- ignore generic types; purpose must be explicitly configured
        else
            deviceType = v
        end
    end

    local config = self:getConfig(name, deviceType)
    local purpose = config.purpose

    if not purpose then
        self.logger.debug("[device] unconfigured device", name, "type", deviceType or "unknown")
        return nil
    end

    if purpose == "crafting" and not deviceType then
        deviceType = config.machineType or config.type
    end

    if purpose == "crafting" then
        if not deviceType then
            self.logger.warn("[device] crafting device missing type", name)
            return nil
        end
        local backend = BackendRegistry.resolve(config.backend)
        local machineClass = resolveMachineClass(deviceType, config)
        local machine = machineClass(self.server, name, deviceType, config, backend)
        self.logger.debug("[device] machine attached", name, "type", deviceType)
        return machine
    elseif purpose == "storage" then
        local storage = Storage(self.server, name, deviceType, config)
        self.logger.debug("[device] storage attached", name, "type", deviceType or "inventory")
        return storage
    end

    if deviceType then
        self.logger.debug("[device] unconfigured device", name, "type", deviceType)
    else
        self.logger.debug("[device] unconfigured device", name, "(unknown type)")
    end
    return nil
end

-- Alias for createDevice (new naming)
function DeviceCatalog:instantiateDevice(name)
    return self:createDevice(name)
end

-- Creates the appropriate Device for the given network peripheral,
-- then adds it to the device table.
function DeviceCatalog:addDevice(name)
    if self.devices[name] then
        self.logger.info("[device] skipped double add device", name)
        --self.devices[name]:destroy()
        return
    end
    self.logger.debug("[device] attach event", name)
    self.devices[name] = self:createDevice(name)
end

-- Removes a device from the device table, clearing any associated state.
function DeviceCatalog:removeDevice(name)
    local device = self.devices[name]
    if device then
        self.logger.debug("[device] detach event", name, "type", device.type or "unknown")
        self.devices[name] = nil
        device:destroy()
    else
        self.logger.warn("[device] double remove device", name)
    end
end

return DeviceCatalog



