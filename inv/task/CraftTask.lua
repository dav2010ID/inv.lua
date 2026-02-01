local Task = require 'inv.task.Task'

-- Represents a crafting operation in progress.
local CraftTask = Task:subclass()

-- dest and destSlot are optional.
function CraftTask:init(server, parent, recipe, dest, destSlot)
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
end

function CraftTask:run()
    if self.nSubTasks > 0 then
        return false
    end
    if not self.machine then
        local missing = self.server.inventoryIndex:tryMatchAll(self.recipe.input)
        if #missing > 0 then
            if not self.dependenciesPlanned and self.server.craftExecutor.planner then
                self.dependenciesPlanned = true
                self.server.craftExecutor.planner:attachDependencies(self, self.recipe, 0, {})
            end
            return false
        end
        self.machine = self.server.craftRegistry:findMachine(self.recipe.machine)
        if not self.machine then
            return false
        end
        if self.machine:craft(self.recipe, self.dest, self.destSlot) == false then
            self.machine = nil
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
