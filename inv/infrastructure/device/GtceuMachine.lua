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

function GtceuMachine:isActive()
    return callInterface(self, "isActive")
end

function GtceuMachine:getProgress()
    return callInterface(self, "getProgress")
end

function GtceuMachine:getMaxProgress()
    return callInterface(self, "getMaxProgress")
end

function GtceuMachine:getInputPerSec()
    return callInterface(self, "getInputPerSec")
end

function GtceuMachine:getOutputPerSec()
    return callInterface(self, "getOutputPerSec")
end

function GtceuMachine:getItemLimit(slot)
    return callInterface(self, "getItemLimit", slot)
end

function GtceuMachine:getEnergyStored()
    return callInterface(self, "getEnergyStored")
end

function GtceuMachine:getEnergyCapacity()
    return callInterface(self, "getEnergyCapacity")
end

function GtceuMachine:isWorkingEnabled()
    return callInterface(self, "isWorkingEnabled")
end

function GtceuMachine:setWorkingEnabled(enabled)
    if enabled == nil then
        enabled = true
    end
    return callInterface(self, "setWorkingEnabled", enabled)
end

function GtceuMachine:setSuspendAfterFinish(enabled)
    if enabled == nil then
        enabled = true
    end
    return callInterface(self, "setSuspendAfterFinish", enabled)
end

function GtceuMachine:isOutputReady(session)
    local active = self:isActive()
    if session and active then
        session._gtceuSeenActive = true
    end
    local progress = self:getProgress()
    local max = self:getMaxProgress()
    if progress ~= nil and max ~= nil and max > 0 then
        return progress >= max
    end
    if session and session._gtceuSeenActive and active == false then
        return true
    end
    return false
end

function GtceuMachine:estimateDuration(craftCount)
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

return GtceuMachine
