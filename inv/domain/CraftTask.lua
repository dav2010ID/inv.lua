local Task = require 'inv.domain.Task'
-- Represents a crafting operation in progress.
local CraftTask = Task:subclass()

-- dest and destSlot are optional.
-- craftCount defaults to 1.
-- priority defaults to 0 (higher runs first).
function CraftTask:init(server, parent, recipe, dest, destSlot, craftCount, summary, priority)
    CraftTask.superClass.init(self, server, parent)
    -- Machine: What is currently crafting this Task's recipe.
    -- nil if we're waiting to find a machine.
    self.machine = nil
    -- Recipe: What should be crafted.
    self.recipe = recipe
    -- Device: Optional. Where crafted items should be sent.
    self.dest = dest
    -- int: Optional. Slot within self.dest where items should be sent.
    self.destSlot = destSlot
    self.dependenciesPlanned = false
    self.craftCount = craftCount or 1
    self.nextAttempt = nil
    self.createdAt = os.clock()
    self.startedAt = nil
    self.machineType = recipe.machine
    self.queuedForMachine = false
    self.summaryId = summary and summary.id or nil
    self.lastMissing = nil
    self.priority = priority or 0
end

function CraftTask:scaledInputs()
    local inputs = {}
    for _, item in pairs(self.recipe.input) do
        local copy = item:copy()
        copy.count = copy.count * self.craftCount
        table.insert(inputs, copy)
    end
    return inputs
end

function CraftTask:assignMachine(machine)
    if not machine then
        return false
    end
    self.machine = machine
    if self.machine:craft(self.recipe, self.dest, self.destSlot, self.craftCount) == false then
        self.machine = nil
        self.server.taskScheduler:setStatus(self, "blocked", "inputs")
        self.nextAttempt = os.clock() + 1
        return false
    end
    self.startedAt = os.clock()
    self.server.taskScheduler:setStatus(self, "running")
    local waitSeconds = self.startedAt - self.createdAt
    if self.summaryId then
        self.server.taskScheduler:recordTaskStart(self.summaryId, self.machineType, waitSeconds)
    end
    local blocker = self.lastMissing
    self.lastMissing = nil
    self.server.logger.debug(
        "[task] start",
        self.recipe.machine,
        "x" .. tostring(self.craftCount),
        "reason: inputs_ready",
        "waited",
        string.format("%.2fs", waitSeconds),
        blocker and ("blocked_by " .. blocker) or ""
    )
    return true
end

function CraftTask:run()
    if self.nextAttempt and os.clock() < self.nextAttempt then
        self.server.taskScheduler:recordWaitProgress(self)
        return false
    end
    if self.queuedForMachine then
        self.server.taskScheduler:recordWaitProgress(self)
        return false
    end
    if self.nSubTasks > 0 then
        return false
    end
    if not self.machine then
        local missing = self.server.inventoryService:tryMatchAll(self:scaledInputs())
        if #missing > 0 then
            self.server.taskScheduler:recordWaitProgress(self)
            self.server.taskScheduler:setStatus(self, "blocked", "inputs")
            local blocker = missing[1]
            if blocker and self.summaryId then
                local name = blocker.name
                if not name and blocker.tags then
                    for tag, _ in pairs(blocker.tags) do
                        name = "tag:" .. tag
                        break
                    end
                end
                if name then
                    self.lastMissing = name
                end
            end
            if not self.dependenciesPlanned and self.server.craftExecutor and self.server.craftExecutor.factory then
                self.dependenciesPlanned = true
                self.server.craftExecutor.factory:attachDependencies(self, self.recipe, 0, {}, self.craftCount, self.summaryId)
            end
            return false
        end
        local machine = self.server.machineScheduler:requestMachine(self)
        if not machine then
            self.server.taskScheduler:setStatus(self, "waiting", "machine")
            self.server.machineScheduler:logSaturation(self.recipe.machine)
            self.nextAttempt = os.clock() + 1
            return false
        end
        if not self:assignMachine(machine) then
            return false
        end
    end
    self.machine:pullOutput()
    if not self.machine:isBusy() then
        local endAt = os.clock()
        local runSeconds = self.startedAt and (endAt - self.startedAt) or 0
        local totalSeconds = endAt - self.createdAt
        if self.summaryId then
            self.server.taskScheduler:recordTaskComplete(self.summaryId, self.machineType, runSeconds)
        end
        self.server.logger.debug(
            "[task] completed",
            self.recipe.machine,
            "x" .. tostring(self.craftCount),
            "on",
            self.machine.name,
            "run",
            string.format("%.2fs", runSeconds),
            "total",
            string.format("%.2fs", totalSeconds)
        )
        self.server.machineScheduler:notifyMachineFree(self.recipe.machine)
        return true
    end
    return false
end

return CraftTask
