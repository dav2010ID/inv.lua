local Object = require 'object.Object'
local Common = require 'inv.Common'
local Config = require 'inv.Config'
local CraftManager = require 'inv.CraftManager'
local DeviceManager = require 'inv.DeviceManager'
local InvManager = require 'inv.InvManager'
local StorageManager = require 'inv.StorageManager'
local RPCMethods = require 'inv.RPCMethods'
local TaskManager = require 'inv.TaskManager'

local Server = Object:subclass()

function Server:init()
    local deviceConfig, recipeConfig = self:loadConfig()
    self:setup(deviceConfig, recipeConfig)
end

function Server:loadConfig()
    local configDir = "config/"
    local deviceConfig = Config.loadDirectory(configDir .. "devices")
    local recipeConfig = Config.loadDirectory(configDir .. "recipes")
    return deviceConfig, recipeConfig
end

function Server:setup(deviceConfig, recipeConfig)
    self.clients = {}

    self.invManager = InvManager(self)
    self.storageManager = StorageManager(self)
    self.deviceManager = DeviceManager(self, deviceConfig)
    self.craftManager = CraftManager(self)
    self.taskManager = TaskManager(self)
    self.rpcMethods = RPCMethods
    self.taskTimer = nil

    self.craftManager:loadRecipes(recipeConfig)
    self.deviceManager:scanDevices()
end

function Server:openNetwork()
    rednet.open(Common.getModemSide())
end

function Server:closeNetwork()
    rednet.close(Common.getModemSide())
end

function Server:send(clientID, message)
    rednet.send(clientID, message, Common.PROTOCOL)
end

function Server:register(clientID)
    self.clients[clientID] = true
end

function Server:unregister(clientID)
    self.clients[clientID] = nil
end

function Server:onMessage(clientID, message, protocol)
    if protocol == Common.PROTOCOL then
        self:register(clientID)
        local method = self.rpcMethods[message[1]]
        if method then
            method(self, clientID, unpack(message[2]))
        end
    end
end

function Server:handlePeripheralAttach(name)
    if peripheral.isPresent(name) then
        self.deviceManager:addDevice(name)
    end
end

function Server:handlePeripheralDetach(name)
    if not peripheral.isPresent(name) then
        self.deviceManager:removeDevice(name)
    end
end

function Server:handleEvent(evt)
    local event = evt[1]
    if event == "rednet_message" then
        self:onMessage(evt[2], evt[3], evt[4])
    elseif event == "peripheral" then
        self:handlePeripheralAttach(evt[2])
    elseif event == "peripheral_detach" then
        self:handlePeripheralDetach(evt[2])
    elseif event == "terminate" then
        return false, false
    end

    local runTasks = true
    if event == "timer" and evt[2] ~= self.taskTimer then
        runTasks = false
    end

    return true, runTasks
end

function Server:updateTasks()
    if self.taskManager:update() then
        self.taskTimer = os.startTimer(1)
        print("[server] active tasks:", #self.taskManager.active)
        --for i,t in pairs(self.taskManager.sleeping) do
        --    print("sleeping",i)
        --end
        --print(math.random(1,100))
    end
end

function Server:broadcastUpdatedItems()
    local updated = self.invManager:getUpdatedItems()
    if not updated then
        return
    end
    local message = {"items", updated}
    --print(textutils.serialize(self.clients))
    for clientID in pairs(self.clients) do
        self:send(clientID, message)
    end
end

function Server:mainLoop()
    self:openNetwork()
    while true do
        local evt = {os.pullEventRaw()}
        local shouldContinue, runTasks = self:handleEvent(evt)
        if not shouldContinue then
            break
        end
        if runTasks then
            self:updateTasks()
        end
        self:broadcastUpdatedItems()
    end
    self:closeNetwork()
end

return Server
