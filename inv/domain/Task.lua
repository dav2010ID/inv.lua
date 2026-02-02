local Object = require 'inv.core.Object'

-- Represents an asynchronous operation performed by the network.
local Task = Object:subclass()

Task.statuses = {
    created = true,
    waiting = true,
    ready = true,
    running = true,
    blocked = true,
    done = true,
    failed = true
}

function Task:init(server, parent)
    self.server = server
    -- Task: Optional. The parent Task of which this Task is a sub-task.
    self.parent = parent
    -- table<int, Task>: Sub-tasks of this Task. The task will be suspended
    -- until these sub-tasks complete. Indexed by task ID.
    self.subTasks = {}
    -- The number of current sub-tasks.
    self.nSubTasks = 0
    -- This task's unique identifier.
    self.id = server.taskScheduler:nextID()
    -- string: current task status (see Task.statuses).
    self.status = "created"
    -- string|nil: reason for current status (e.g. "inputs", "machine", "subtasks").
    self.statusReason = nil
    -- number: time when status last changed.
    self.lastStatusAt = os.clock()
    
    if self.parent then
        self.parent.subTasks[self.id] = self
        self.parent.nSubTasks = self.parent.nSubTasks + 1
    end
end

-- Continues the operation being performed by this task.
-- Returns true if the operation is complete.
function Task:run()
    return true
end

-- Updates the task status. Intended for use by TaskScheduler.
function Task:setStatus(newStatus, reason, at)
    assert(Task.statuses[newStatus], "unknown task status: " .. tostring(newStatus))
    self.status = newStatus
    self.statusReason = reason
    self.lastStatusAt = at or os.clock()
end

-- Destroys the task, cleaning up associated state.
function Task:destroy()
    if self.parent then
        self.parent.subTasks[self.id] = nil
        self.parent.nSubTasks = self.parent.nSubTasks - 1
    end
end

return Task

