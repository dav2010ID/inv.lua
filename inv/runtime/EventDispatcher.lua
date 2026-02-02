local Class = require 'inv.core.Class'

local EventDispatcher = Class:subclass()

function EventDispatcher:init(server, cli)
    self.server = server
    self.cli = cli
    self.logger = server.logger
end

function EventDispatcher:handlePeripheralAttach(name)
    if peripheral.isPresent(name) then
        self.logger.debug("[event] peripheral attach", name)
        self.server.deviceCatalog:addDevice(name)
    end
end

function EventDispatcher:handlePeripheralDetach(name)
    if not peripheral.isPresent(name) then
        self.logger.debug("[event] peripheral detach", name)
        self.server.deviceCatalog:removeDevice(name)
    end
end

function EventDispatcher:handleEvent(evt)
    local event = evt[1]
    if event == "peripheral" then
        self:handlePeripheralAttach(evt[2])
    elseif event == "peripheral_detach" then
        self:handlePeripheralDetach(evt[2])
    elseif event == "terminate" then
        return false
    elseif event == "char" then
        if self.cli then
            self.cli:onChar(evt[2])
        end
    elseif event == "key" then
        if self.cli then
            self.cli:onKey(evt[2])
        end
    end

    return true
end

return EventDispatcher



