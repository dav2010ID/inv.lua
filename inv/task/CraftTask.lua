local Task = require 'inv.task.Task'
local Log = require 'inv.Log'
-- Represents a crafting operation in progress.
local CraftTask = Task:subclass()

-- dest and destSlot are optional.
-- craftCount defaults to 1.
function CraftTask:init(server, parent, recipe, dest, destSlot, craftCount)
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

function CraftTask:run()
    if self.nextAttempt and os.clock() < self.nextAttempt then
        return false
    end
    if self.nSubTasks > 0 then
        return false
    end
    if not self.machine then
        local missing = self.server.inventoryIndex:tryMatchAll(self:scaledInputs())
        if #missing > 0 then
            self.status = "waiting_inputs"
            if not self.dependenciesPlanned and self.server.craftExecutor.planner then
                self.dependenciesPlanned = true
                self.server.craftExecutor.planner:attachDependencies(self, self.recipe, 0, {}, self.craftCount)
            end
            return false
        end
        self.machine = self.server.craftRegistry:findMachine(self.recipe.machine)
        if not self.machine then
            self.status = "waiting_machine"
            self.nextAttempt = os.clock() + 1
            return false
        end
        if self.machine:craft(self.recipe, self.dest, self.destSlot, self.craftCount) == false then
            self.machine = nil
            self.status = "waiting_inputs"
            self.nextAttempt = os.clock() + 1
            return false
        end
        self.startedAt = os.clock()
        self.status = "running"
        local waitSeconds = self.startedAt - self.createdAt
        Log.debug(
            "[task] started",
            self.recipe.machine,
            "x" .. tostring(self.craftCount),
            "on",
            self.machine.name,
            "wait",
            string.format("%.2fs", waitSeconds)
        )
    end
    self.machine:pullOutput()
    if not self.machine:busy() then
        self.status = "done"
        local endAt = os.clock()
        local runSeconds = self.startedAt and (endAt - self.startedAt) or 0
        local totalSeconds = endAt - self.createdAt
        Log.debug(
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
        return true
    end
    return false
end

return CraftTask
