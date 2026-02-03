local Class = require 'inv.core.Class'

-- Represents an asynchronous operation performed by the network.
local Task = Class:subclass()

Task.STATUS = {
    CREATED = "created",
    WAITING = "waiting",
    READY = "ready",
    RUNNING = "running",
    BLOCKED = "blocked",
    DONE = "done",
    FAILED = "failed"
}

Task.STATUS_ORDER = {
    Task.STATUS.CREATED,
    Task.STATUS.WAITING,
    Task.STATUS.READY,
    Task.STATUS.RUNNING,
    Task.STATUS.BLOCKED,
    Task.STATUS.DONE,
    Task.STATUS.FAILED
}

local STATUS_SET = {}
for _, value in pairs(Task.STATUS) do
    STATUS_SET[value] = true
end

function Task:init(server, parent)
    self.server = server
    -- Task: Optional. The parent Task of which this Task is a sub-task.
    self.parent = parent
    -- table<int, Task>: Sub-tasks of this Task. The task will be suspended
    -- until these sub-tasks complete. Indexed by task ID.
    self.subTasks = {}
    -- The number of current sub-tasks.
    self.nSubTasks = 0
    -- This task's unique identifier (assigned by TaskScheduler).
    self.id = nil
    -- number: creation time (immutable).
    self.createdAt = os.clock()
    -- string: current task status (see Task.STATUS).
    self.status = Task.STATUS.CREATED
    -- string|nil: reason for current status (e.g. "inputs", "machine", "subtasks").
    self.statusReason = nil
    -- string|nil: reason for blocked status.
    self.blockReason = nil
    -- string|nil: item or tag currently blocking this task.
    self.blockedBy = nil
    -- number: time when status last changed.
    self.lastStatusAt = os.clock()
end

-- Continues the operation being performed by this task.
-- Returns true only when the task has reached a terminal state.
function Task:run()
    return true
end

-- Applies a status transition. Intended for use by TaskScheduler only.
function Task:applyStatus(newStatus, reason, at, blockedBy)
    assert(STATUS_SET[newStatus], "unknown task status: " .. tostring(newStatus))
    if newStatus == self.status and reason == self.statusReason and blockedBy == self.blockedBy then
        return
    end
    self.status = newStatus
    self.statusReason = reason
    if newStatus == Task.STATUS.BLOCKED then
        self.blockReason = reason
        if blockedBy ~= nil then
            self.blockedBy = blockedBy
        end
    else
        self:clearBlock()
    end
    self.lastStatusAt = at or os.clock()
end

function Task:clearBlock()
    self.blockReason = nil
    self.blockedBy = nil
end

function Task:attachToParent()
    if not self.parent then
        return
    end
    assert(self.id ~= nil, "task id required before attaching to parent")
    local existing = self.parent.subTasks[self.id]
    if existing == self then
        return
    end
    assert(existing == nil, "task already registered in parent")
    self.parent.subTasks[self.id] = self
    self.parent.nSubTasks = self.parent.nSubTasks + 1
end

function Task:detachFromParent()
    if not self.parent then
        return
    end
    assert(self.parent.subTasks[self.id] == self, "task not registered in parent")
    self.parent.subTasks[self.id] = nil
    assert(self.parent.nSubTasks > 0, "parent subtask count underflow")
    self.parent.nSubTasks = self.parent.nSubTasks - 1
end

-- Called when a child task completes. Override in subclasses if needed.
function Task:onChildDone(child) end

-- Destroys the task, cleaning up associated state.
function Task:destroy()
    self:detachFromParent()
end

return Task
