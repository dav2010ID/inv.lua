local Task = require 'inv.task.Task'
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
    self.status = "waiting_inputs"
    self.queuedForMachine = false
    self.summaryId = summary and summary.id or nil
    self.lastStatusAt = self.createdAt
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
        self:setStatus("waiting_inputs")
        self.nextAttempt = os.clock() + 1
        return false
    end
    self.startedAt = os.clock()
    self:setStatus("running")
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

function CraftTask:setStatus(newStatus)
    if self.status == newStatus then
        return
    end
    if self.summaryId and (self.status == "waiting_machine" or self.status == "waiting_inputs") then
        local now = os.clock()
        local waited = now - self.lastStatusAt
        self.server.taskScheduler:recordWait(self.summaryId, self.machineType, self.status, waited)
        if self.status == "waiting_inputs" and self.lastMissing then
            self.server.taskScheduler:recordInputBlocker(self.summaryId, self.machineType, self.lastMissing, waited)
            self.lastMissing = nil
        end
        self.lastStatusAt = now
    else
        self.lastStatusAt = os.clock()
    end
    self.status = newStatus
end

function CraftTask:run()
    if self.nextAttempt and os.clock() < self.nextAttempt then
        return false
    end
    if self.queuedForMachine then
        return false
    end
    if self.nSubTasks > 0 then
        return false
    end
    if not self.machine then
        local missing = self.server.inventoryService:tryMatchAll(self:scaledInputs())
        if #missing > 0 then
            local now = os.clock()
            if self.summaryId and self.status == "waiting_inputs" then
                local waited = now - self.lastStatusAt
                if waited > 0 then
                    self.server.taskScheduler:recordWait(self.summaryId, self.machineType, "waiting_inputs", waited)
                    if self.lastMissing then
                        self.server.taskScheduler:recordInputBlocker(self.summaryId, self.machineType, self.lastMissing, waited)
                    end
                    self.lastStatusAt = now
                end
            end
            self:setStatus("waiting_inputs")
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
            if not self.dependenciesPlanned and self.server.craftRunner.planner then
                self.dependenciesPlanned = true
                self.server.craftRunner.planner:attachDependencies(self, self.recipe, 0, {}, self.craftCount)
            end
            return false
        end
        local machine = self.server.machineScheduler:requestMachine(self)
        if not machine then
            self:setStatus("waiting_machine")
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
        self:setStatus("done")
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
