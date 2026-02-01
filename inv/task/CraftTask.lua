local Task = require 'inv.task.Task'

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
            if not self.dependenciesPlanned and self.server.craftExecutor.planner then
                self.dependenciesPlanned = true
                self.server.craftExecutor.planner:attachDependencies(self, self.recipe, 0, {}, self.craftCount)
            end
            return false
        end
        self.machine = self.server.craftRegistry:findMachine(self.recipe.machine)
        if not self.machine then
            self.nextAttempt = os.clock() + 1
            return false
        end
        if self.machine:craft(self.recipe, self.dest, self.destSlot, self.craftCount) == false then
            self.machine = nil
            self.nextAttempt = os.clock() + 1
            return false
        end
    end
    self.machine:pullOutput()
    if not self.machine:busy() then
        return true
    end
    return false
end

return CraftTask
