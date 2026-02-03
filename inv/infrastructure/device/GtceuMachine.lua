local Machine = require 'inv.infrastructure.device.Machine'

-- Extends Machine with GTCEu-specific helpers.
local GtceuMachine = Machine:subclass()

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
    if self.cap and self.cap.working then
        local enabled = self:isWorkingEnabled()
        if enabled == false then
            return false
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
