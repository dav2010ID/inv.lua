local Task = require 'inv.domain.Task'
-- Represents a crafting operation in progress.
local CraftTask = Task:subclass()

CraftTask.states = {
    created = true,
    waiting_inputs = true,
    waiting_machine = true,
    running = true,
    done = true,
    failed = true
}

-- dest and destSlot are optional.
-- craftCount defaults to 1.
-- priority defaults to 0 (higher runs first).
function CraftTask:init(server, parent, recipe, dest, destSlot, craftCount, summary, priority)
    CraftTask.superClass.init(self, server, parent)
    -- Recipe: What should be crafted.
    self.recipe = recipe
    -- Device: Optional. Where crafted items should be sent.
    self.dest = dest
    -- int: Optional. Slot within self.dest where items should be sent.
    self.destSlot = destSlot
    self.craftCount = craftCount or 1
    self.createdAt = os.clock()
    self.startedAt = nil
    self.machineType = recipe.machine
    self.summaryId = summary and summary.id or nil
    self.priority = priority or 0
    self.state = "created"
    self.retryAfter = nil
    self.needsDependencies = true
    self._scaledInputs = nil
    self.machineName = nil
end

function CraftTask:scaledInputs()
    if self._scaledInputs then
        return self._scaledInputs
    end
    local inputs = self.recipe:scaledInputs(self.craftCount)
    self._scaledInputs = inputs
    return inputs
end

function CraftTask:wantsInputs()
    return self.state == "created" or self.state == "waiting_inputs" or self.state == "waiting_machine"
end

function CraftTask:wantsMachine()
    return self.state == "created" or self.state == "waiting_machine"
end

function CraftTask:canRun()
    return self.state == "running"
end

function CraftTask:bindMachine(machine)
    self.machineName = machine and machine.name or nil
end

function CraftTask:startExecution(at)
    self.startedAt = at or os.clock()
end

function CraftTask:onStartSuccess()
    self.state = "running"
end

function CraftTask:onStartFailure(reason)
    if reason == "inputs" then
        self.state = "waiting_inputs"
    elseif reason == "machine" then
        self.state = "waiting_machine"
    else
        self.state = "created"
    end
end

function CraftTask:run()
    if self.state == "created" then
        return false
    elseif self.state == "waiting_inputs" then
        return false
    elseif self.state == "waiting_machine" then
        return false
    elseif self.state == "running" then
        return false
    elseif self.state == "done" or self.state == "failed" then
        return true
    end
    return false
end

return CraftTask
