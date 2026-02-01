local Object = require 'object.Object'

-- Asynchronously manages crafting tasks
local TaskManager = Object:subclass()

function TaskManager:init(server)
    self.server = server
    -- table<int, Task>: Tasks that are currently performing an operation,
    -- e.g. counting and storing output items from a crafting machine.
    self.active = {}
    -- table<int, Task>: Tasks that are waiting for another task to complete.
    -- Indexed by task ID.
    self.sleeping = {}
    -- The last ID assigned to a task.
    self.lastID = 0
end

-- Returns the next available task ID for creating a new task.
function TaskManager:nextID()
    self.lastID = self.lastID + 1
    return self.lastID
end

-- Updates all running tasks, sleeping parent tasks when they create sub-tasks
-- and resuming them when the sub-tasks complete.
function TaskManager:update()
    --print("calling update")
    local i = 1
    while i <= #self.active do
        local task = self.active[i]
        if task:run() then
            table.remove(self.active, i)
            local parent = task.parent
            task:destroy()
            if parent and parent.nSubTasks == 0 then
                self.sleeping[parent.id] = nil
                table.insert(self.active, parent)
            end
        elseif task.nSubTasks > 0 then
            table.remove(self.active, i)
            self.sleeping[task.id] = task
        else
            i = i + 1
        end
    end
    if #self.active > 0 then
        return true
    end
    return false
end

-- Adds a new task, and designates it as active.
function TaskManager:addTask(task)
    table.insert(self.active, task)
end

function TaskManager:getMachineStats()
    local stats = {}

    local function add(task)
        if not task or not task.machineType or not task.status then
            return
        end
        local entry = stats[task.machineType]
        if not entry then
            entry = {waiting_inputs=0, waiting_machine=0, running=0, waiting_subtasks=0, total=0}
            stats[task.machineType] = entry
        end
        entry.total = entry.total + 1
        if task.nSubTasks and task.nSubTasks > 0 then
            entry.waiting_subtasks = entry.waiting_subtasks + 1
            return
        end
        if task.status == "waiting_inputs" then
            entry.waiting_inputs = entry.waiting_inputs + 1
        elseif task.status == "waiting_machine" then
            entry.waiting_machine = entry.waiting_machine + 1
        elseif task.status == "running" then
            entry.running = entry.running + 1
        end
    end

    for _, task in ipairs(self.active) do
        add(task)
    end
    for _, task in pairs(self.sleeping) do
        add(task)
    end

    return stats
end

return TaskManager
