local Machine = require 'inv.infrastructure.device.Machine'
local Log = require 'inv.infrastructure.Log'
-- Extends Machine with GTCEu-specific helpers.
local GtceuMachine = Machine:subclass()

local CIRCUIT_NBT_KEYS = {
    "Configuration",
    "configuration",
    "Config",
    "config",
    "Circuit",
    "circuit",
    "circuit_number",
    "CircuitNumber"
}

local function addModifier(set, value)
    if value and value ~= "" then
        set[value] = true
    end
end

local function moldKeyFromName(name)
    if not name then
        return nil
    end
    local key = string.match(name, "^gtceu:shape_mold_(.+)$")
    if not key then
        key = string.match(name, "^gtceu:shape_extruder_(.+)$")
    end
    if not key then
        key = string.match(name, "^gtceu:mold_(.+)$")
    end
    if not key then
        key = string.match(name, "^gtceu:extruder_mold_(.+)$")
    end
    return key
end

local function findCircuitValueInTable(tbl, depth)
    if type(tbl) ~= "table" then
        return nil
    end
    depth = depth or 0
    if depth > 4 then
        return nil
    end
    for _, key in ipairs(CIRCUIT_NBT_KEYS) do
        local v = tbl[key]
        if type(v) == "number" then
            return v
        end
        if type(v) == "string" then
            local num = tonumber(v)
            if num ~= nil then
                return num
            end
        end
    end
    for _, v in pairs(tbl) do
        if type(v) == "table" then
            local found = findCircuitValueInTable(v, depth + 1)
            if found ~= nil then
                return found
            end
        end
    end
    return nil
end

local function findCircuitValueInString(nbt)
    if type(nbt) ~= "string" then
        return nil
    end
    local patterns = {
        "[Cc]onfiguration:%s*(-?%d+)",
        "[Cc]onfig:%s*(-?%d+)",
        "[Cc]ircuit:%s*(-?%d+)",
        "[Cc]ircuit[Nn]umber:%s*(-?%d+)"
    }
    for _, pattern in ipairs(patterns) do
        local value = string.match(nbt, pattern)
        if value then
            return tonumber(value)
        end
    end
    return nil
end

local function extractCircuitModifier(detail)
    if not detail or not detail.name then
        return nil
    end
    if not string.find(detail.name, "circuit", 1, true) then
        return nil
    end
    local nbt = detail.nbt
    local num = nil
    if type(nbt) == "table" then
        num = findCircuitValueInTable(nbt, 0)
    elseif type(nbt) == "string" then
        num = findCircuitValueInString(nbt)
    end
    if num ~= nil then
        return "circuit:" .. tostring(num)
    end
    return "circuit"
end

local function extractModifiers(detail)
    local mods = {}
    if not detail or not detail.name then
        return mods
    end
    local moldKey = moldKeyFromName(detail.name)
    if moldKey then
        addModifier(mods, "mold:" .. moldKey)
    end
    local circuit = extractCircuitModifier(detail)
    if circuit then
        addModifier(mods, circuit)
    end
    return mods
end

function GtceuMachine:getDynamicModifiers()
    local mods = {}
    local slots = nil
    if self.config and type(self.config.modifierSlots) == "table" then
        slots = self.config.modifierSlots
    end
    local function readDetail(slot)
        if not self.interface or type(self.interface.getItemDetail) ~= "function" then
            return nil
        end
        local ok, detail = pcall(function()
            return self.interface.getItemDetail(slot, true)
        end)
        if ok and detail then
            return detail
        end
        return self:getItemDetail(slot)
    end
    if slots then
        for _, slot in ipairs(slots) do
            local detail = readDetail(slot)
            if detail then
                local found = extractModifiers(detail)
                for key, _ in pairs(found) do
                    addModifier(mods, key)
                end
            end
        end
        return mods
    end
    if self.interface and type(self.interface.list) == "function" then
        local items = self.interface.list()
        for slot, _ in pairs(items) do
            local detail = readDetail(slot)
            if detail then
                local found = extractModifiers(detail)
                for key, _ in pairs(found) do
                    addModifier(mods, key)
                end
            end
        end
    end
    return mods
end

function GtceuMachine:hasModifiers(required)
    if not required then
        return true
    end
    local available = {}
    if self.modifiers then
        for key, _ in pairs(self.modifiers) do
            addModifier(available, key)
        end
    end
    local dynamic = self:getDynamicModifiers()
    for key, _ in pairs(dynamic) do
        addModifier(available, key)
    end
    for key, _ in pairs(required) do
        if not available[key] then
            return false
        end
    end
    return true
end

local function callInterface(self, name, ...)
    local iface = self.interface
    if not iface then
        return nil
    end
    local fn = iface[name]
    if type(fn) ~= "function" then
        return nil
    end
    return fn(...)
end

function GtceuMachine:init(server, name, deviceType, config, backend)
    GtceuMachine.superClass.init(self, server, name, deviceType, config, backend)
    local iface = self.interface
    self.cap = {
        active = iface and type(iface.isActive) == "function" or false,
        progress = iface and type(iface.getProgress) == "function" and type(iface.getMaxProgress) == "function" or false,
        ioRate = iface and (type(iface.getInputPerSec) == "function" or type(iface.getOutputPerSec) == "function") or false,
        limits = iface and type(iface.getItemLimit) == "function" or false,
        energy = iface and (type(iface.getEnergyStored) == "function" or type(iface.getEnergyCapacity) == "function") or false,
        working = iface and type(iface.isWorkingEnabled) == "function" or false
    }
end

function GtceuMachine:isActive()
    if not self.cap or not self.cap.active then
        return nil
    end
    return callInterface(self, "isActive")
end

function GtceuMachine:getProgress()
    if not self.cap or not self.cap.progress then
        return nil
    end
    return callInterface(self, "getProgress")
end

function GtceuMachine:getMaxProgress()
    if not self.cap or not self.cap.progress then
        return nil
    end
    return callInterface(self, "getMaxProgress")
end

function GtceuMachine:getInputPerSec()
    if not self.cap or not self.cap.ioRate then
        return nil
    end
    return callInterface(self, "getInputPerSec")
end

function GtceuMachine:getOutputPerSec()
    if not self.cap or not self.cap.ioRate then
        return nil
    end
    return callInterface(self, "getOutputPerSec")
end

function GtceuMachine:getItemLimit(slot)
    if not self.cap or not self.cap.limits then
        return nil
    end
    return callInterface(self, "getItemLimit", slot)
end

function GtceuMachine:getEnergyStored()
    if not self.cap or not self.cap.energy then
        return nil
    end
    return callInterface(self, "getEnergyStored")
end

function GtceuMachine:getEnergyCapacity()
    if not self.cap or not self.cap.energy then
        return nil
    end
    return callInterface(self, "getEnergyCapacity")
end

function GtceuMachine:isWorkingEnabled()
    if not self.cap or not self.cap.working then
        return nil
    end
    return callInterface(self, "isWorkingEnabled")
end

function GtceuMachine:setWorkingEnabled(enabled)
    if not self.cap or not self.cap.working then
        return nil
    end
    if enabled == nil then
        enabled = true
    end
    return callInterface(self, "setWorkingEnabled", enabled)
end

function GtceuMachine:setSuspendAfterFinish(enabled)
    if not self.cap or not self.cap.working then
        return nil
    end
    if enabled == nil then
        enabled = true
    end
    return callInterface(self, "setSuspendAfterFinish", enabled)
end

function GtceuMachine:isOutputReady(session)
    if not self.cap or not self.cap.active then
        return true
    end
    local active = self:isActive()
    if active then
        return false
    end
    return true
end

function GtceuMachine:estimateDuration(recipe, craftCount)
    if type(recipe) == "number" and craftCount == nil then
        craftCount = recipe
        recipe = nil
    end
    local max = self:getMaxProgress()
    if not max or max <= 0 then
        return nil
    end
    local rate = self:getInputPerSec()
    if not rate or rate <= 0 then
        rate = self:getOutputPerSec()
    end
    if not rate or rate <= 0 then
        return nil
    end
    local count = craftCount or 1
    if count < 1 then
        count = 1
    end
    return (max / rate) * count
end

function GtceuMachine:canAcceptTasks(task)
    if not GtceuMachine.superClass.canAcceptTasks(self, task) then
        return false
    end
    if self.cap and self.cap.working then
        local enabled = self:isWorkingEnabled()
        if enabled == false then
            local taskMachine = task and task.recipe and task.recipe.machine or task and task.machineType or nil
            if taskMachine and taskMachine ~= self.type then
                return false
            end
        end
    end
    if self.cap and self.cap.energy then
        local stored = self:getEnergyStored()
        if stored ~= nil and stored <= 0 then
            return false
        end
    end
    return true
end

return GtceuMachine
