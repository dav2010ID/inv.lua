local Machine = require 'inv.infrastructure.device.Machine'
local Log = require 'inv.infrastructure.Log'
-- Extends Machine with GTCEu-specific helpers.
local GtceuMachine = Machine:subclass()

local CIRCUIT_BY_NBT = {
    ["ad0ac2cdf646644c3b06f2de1fc6894c"] = 0,
    ["2f0eaa46331854247963f193b385a9c3"] = 1,
    ["d3efb6f62c113da0c42048aef4b8b803"] = 2,
    ["d009a22f06bca83db0e373efe68f9586"] = 3,
    ["236a18a75613e813a837d0859ce44b3b"] = 4,
    ["99c6a0cf861be9bb86943299ab26fc5f"] = 5,
    ["e61d93226ec25a873381f6f65e52ec9b"] = 6,
    ["7df1801d048aa41b14814337494c946b"] = 7,
    ["65426174b28f3e9d1f64b7a547888acb"] = 8,
    ["d42b93031932ce30d8b116972e10812f"] = 9,
    ["d8cbf08b757e6b2e5027c642247d51ec"] = 10,
    ["eaa5be8a9d484ac8a36da658334d4cfb"] = 11,
    ["c9c82b8d11af99dcb0a7d9ad7a8da0ed"] = 12,
    ["89b6aaaabb18fdd0e5ac7cfb8c93d2ca"] = 13,
    ["3db3679106deff3bc2e02d7d5e6125dd"] = 14,
    ["951843314b12691272f22292c383da8d"] = 15,
    ["14b3c9139de19e3f856911e995aff0a9"] = 16,
    ["29895118229ea3c8df99d6aabf74d570"] = 17,
    ["b10d3805ba6791b0aa99a6fae7083aa3"] = 18,
    ["3a2f9ebca473a5a8c32319deade7eb3d"] = 19,
    ["984bace4fb3f692fb7802730a5c41248"] = 20,
    ["d1299bcd8a5a1bb553b89a5d60bc9b65"] = 21,
    ["ff019e29f1ab51f7df186a99e253362f"] = 22,
    ["50c2930699283adf303af32e1c14484a"] = 23,
    ["f6473b086addbf86f9fa168e19d8175b"] = 24,
    ["778c250e092f05ad7156a63ca4d4c1fd"] = 25,
    ["e5de432e06c3980a30aaf4b18d798b83"] = 26,
    ["08d59c85b4dae474c1d57a10270f8cad"] = 27,
    ["3da0d9033424a9da70807f3c1c92ddd3"] = 28,
    ["71924d5e0069766bd45ef30bfa12575d"] = 29,
    ["a606bab3d2ff05588b7776636132ba56"] = 30,
    ["f8ee067ae43b21713f9445253dc50ea0"] = 31,
    ["b42bf02e2466cdfbaec693eec0adbc78"] = 32
}

local function buildModifierSlotList(self)
    local configured = self.config and self.config.modifierSlots or nil
    if type(configured) == "table" and #configured > 0 then
        local slots = {}
        for _, slot in ipairs(configured) do
            local n = tonumber(slot)
            if n then
                table.insert(slots, n)
            end
        end
        return slots
    end

    local items = self:list()
    local slots = {}
    for slot, _ in pairs(items) do
        table.insert(slots, tonumber(slot) or slot)
    end
    return slots
end

local function mergeModifiers(base, extra)
    local out = {}
    for modifier, value in pairs(base or {}) do
        if value then
            out[modifier] = true
        end
    end
    for modifier, value in pairs(extra or {}) do
        if value then
            out[modifier] = true
        end
    end
    return out
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

function GtceuMachine:getDynamicModifiers()
    local modifiers = {}
    local slots = buildModifierSlotList(self)
    for _, slot in ipairs(slots) do
        local detail = self:getItemDetail(slot)
        if detail and detail.name == "gtceu:programmed_circuit" then
            local circuit = detail.nbt and CIRCUIT_BY_NBT[detail.nbt] or nil
            if circuit ~= nil then
                modifiers["circuit:" .. tostring(circuit)] = true
            end
        end
    end
    return modifiers
end

function GtceuMachine:canAcceptTasks(task)
    local recipe = task and task.recipe or nil
    local recipeModifiers = recipe and recipe.modifiers or nil
    if recipeModifiers and next(recipeModifiers) ~= nil then
        local machineModifiers = mergeModifiers(self.modifiers, self:getDynamicModifiers())
        for modifier, _ in pairs(recipeModifiers) do
            if not machineModifiers[modifier] then
                return false
            end
        end
    elseif not GtceuMachine.superClass.canAcceptTasks(self, task) then
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
