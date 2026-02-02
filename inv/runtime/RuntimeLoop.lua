local Class = require 'inv.core.Class'

local RuntimeLoop = Class:subclass()

function RuntimeLoop:init(server, dispatcher, cli)
    self.server = server
    self.dispatcher = dispatcher
    self.cli = cli
    self.taskTimer = nil
    self.running = true
    self.lastActiveCount = nil
    self.lastActiveLogTime = 0
end

function RuntimeLoop:stop()
    self.running = false
end

function RuntimeLoop:tick()
    if self.server.taskScheduler:tick() then
        self.taskTimer = os.startTimer(1)
        local activeCount = #self.server.taskScheduler.active
        local now = os.clock()
        if self.lastActiveCount ~= activeCount or (now - self.lastActiveLogTime) > 5 then
            self.server.logger.info("[server] active tasks:", activeCount)
            self.lastActiveCount = activeCount
            self.lastActiveLogTime = now
        end
    end
end

function RuntimeLoop:broadcastUpdatedItems()
    self.server.inventoryMutator:getUpdatedItems()
end

function RuntimeLoop:run()
    while self.running do
        local evt = {os.pullEventRaw()}
        local shouldContinue = true
        if self.dispatcher then
            shouldContinue = self.dispatcher:handleEvent(evt)
        end
        if not shouldContinue then
            break
        end
        local runTasks = true
        if evt[1] == "timer" and evt[2] ~= self.taskTimer then
            runTasks = false
        end
        if runTasks then
            self:tick()
        end
        self:broadcastUpdatedItems()
        if self.cli then
            self.cli:drawPrompt()
        end
    end
end

return RuntimeLoop



