local Class = require 'inv.core.Class'

local RuntimeLoop = Class:subclass()
local TASK_TICK_SECONDS = 0.25
local TASK_TICK_BURST = 3

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
    local ran = false
    for _ = 1, TASK_TICK_BURST do
        if not self.server.taskScheduler:tick() then
            break
        end
        ran = true
    end
    if not ran then
        return
    end
    self.taskTimer = os.startTimer(TASK_TICK_SECONDS)
    local activeCount = #self.server.taskScheduler.active
    local now = os.clock()
    if self.lastActiveCount ~= activeCount or (now - self.lastActiveLogTime) > 5 then
        self.cli:status()
        self.lastActiveCount = activeCount
        self.lastActiveLogTime = now
    end
end

function RuntimeLoop:broadcastUpdatedItems()
    self.server.inventoryMutator:getUpdatedItems()
end

function RuntimeLoop:run()
    -- Kick off queued tasks before waiting on the first event.
    self:tick()
    while self.running do
        local evt = { os.pullEventRaw() }
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
        if self.cli and self.cli.tick then
            self.cli:tick()
        end
        if self.cli then
            self.cli:drawPrompt()
        end
    end
end

return RuntimeLoop
