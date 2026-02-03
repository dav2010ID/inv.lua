local Class = require 'inv.core.Class'

-- Schedules tasks onto machines and tracks saturation/queues.
local MachineScheduler = Class:subclass()

function MachineScheduler:init(server, machineRegistry)
    self.server = server
    self.logger = server.logger
    self.machineRegistry = machineRegistry
    -- table<string, table<int, CraftTask>>: queues per machine type.
    self.waitingTasks = {}
    self.queued = {}
end

local function enqueue(machineScheduler, machineType, task)
    if not machineScheduler.waitingTasks[machineType] then
        machineScheduler.waitingTasks[machineType] = {}
    end
    local queue = machineScheduler.waitingTasks[machineType]
    local critical = machineScheduler.server and machineScheduler.server.taskScheduler and machineScheduler.server.taskScheduler.currentCriticalMachine
    local bonus = (critical and critical == machineType) and 1000 or 0
    local priority = (task.priority or 0) + bonus
    local inserted = false
    for i = 1, #queue do
        local other = queue[i]
        local otherPriority = (other.priority or 0) + ((critical and critical == machineType) and 1000 or 0)
        if priority > otherPriority then
            table.insert(queue, i, task)
            inserted = true
            break
        end
    end
    if not inserted then
        table.insert(queue, task)
    end
end

function MachineScheduler:schedule(task)
    local machineType = task.machineType
    local machinesOfType = self.machineRegistry and self.machineRegistry:getMachines(machineType) or nil
    local queue = self.waitingTasks[machineType]
    local queuedTask = queue and queue[1] or nil
    if machinesOfType then
        for _, machine in pairs(machinesOfType) do
            if not machine:isBusy() then
                if queuedTask and queuedTask ~= task then
                    return nil
                end
                if queuedTask == task then
                    table.remove(queue, 1)
                    self.queued[task.id] = nil
                end
                return machine
            end
        end
    end
    if not self.queued[task.id] then
        enqueue(self, machineType, task)
        self.queued[task.id] = true
    end
    return nil
end

function MachineScheduler:countAvailableMachines(machineType)
    local machinesOfType = self.machineRegistry and self.machineRegistry:getMachines(machineType) or nil
    if not machinesOfType then
        return 0
    end
    local n = 0
    for _, machine in pairs(machinesOfType) do
        if not machine:isBusy() then
            n = n + 1
        end
    end
    return n
end

function MachineScheduler:findMachine(machineType)
    local machinesOfType = self.machineRegistry and self.machineRegistry:getMachines(machineType) or nil
    if machinesOfType then
        for _, machine in pairs(machinesOfType) do
            if not machine:isBusy() then
                return machine
            end
        end
    end
    return nil
end

function MachineScheduler:notifyMachineFree(machineType)
    -- Tasks will claim machines on the next scheduler tick via schedule.
end

function MachineScheduler:logSaturation(machineType)
    local machinesOfType = self.machineRegistry and self.machineRegistry:getMachines(machineType) or nil
    if not machinesOfType then
        self.logger.throttle(
            "craft_none_" .. tostring(machineType),
            2,
            self.logger.levels.warn,
            "[warn] ",
            "[craft] no",
            machineType,
            "found"
        )
        return
    end
    local total = 0
    local busy = 0
    for _, machine in pairs(machinesOfType) do
        total = total + 1
        if machine:isBusy() then
            busy = busy + 1
        end
    end
    local waiting = 0
    if self.server and self.server.taskScheduler then
        local stats = self.server.taskScheduler:getMachineStats()
        local entry = stats[machineType]
        waiting = entry and entry.waiting_machine or 0
    end
    self.logger.throttle(
        "craft_saturated_" .. tostring(machineType),
        2,
        self.logger.levels.warn,
        "[warn] ",
        "[craft]",
        machineType,
        "saturated",
        "(" .. tostring(busy) .. "/" .. tostring(total) .. " busy, " .. tostring(waiting) .. " waiting)"
    )
end

function MachineScheduler:logMachineSummary()
    if not self.server or not self.server.taskScheduler or not self.machineRegistry then
        return
    end
    local stats = self.server.taskScheduler:getMachineStats()
    self.logger.info("[planner] machines:")
    for machineType, entry in pairs(stats) do
        local total = self.machineRegistry:countMachines(machineType)
        local available = self:countAvailableMachines(machineType)
        self.logger.info(
            "  " .. machineType .. ":",
            tostring(available) .. " available,",
            tostring(total) .. " total,",
            tostring(entry.total) .. " tasks,",
            tostring(entry.waiting_machine) .. " waiting_machine,",
            tostring(entry.waiting_inputs) .. " waiting_inputs"
        )
    end
end

function MachineScheduler:setCriticalMachine()
    if not self.server or not self.server.taskScheduler or not self.machineRegistry then
        return
    end
    local stats = self.server.taskScheduler:getMachineStats()
    local critical = nil
    local criticalRatio = -1
    for machineType, entry in pairs(stats) do
        local count = self.machineRegistry:countMachines(machineType)
        if count > 0 then
            local ratio = entry.total / count
            if ratio > criticalRatio then
                criticalRatio = ratio
                critical = machineType
            end
        end
    end
    self.server.taskScheduler.currentCriticalMachine = critical
end

return MachineScheduler



