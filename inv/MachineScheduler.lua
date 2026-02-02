local Object = require 'object.Object'

-- Schedules tasks onto machines and tracks saturation/queues.
local MachineScheduler = Object:subclass()

function MachineScheduler:init(server, machinePool)
    self.server = server
    self.logger = server.logger
    self.machinePool = machinePool
    -- table<string, table<int, CraftTask>>: queues per machine type.
    self.waitingTasks = {}
end

function MachineScheduler:enqueueTask(machineType, task)
    if not self.waitingTasks[machineType] then
        self.waitingTasks[machineType] = {}
    end
    local queue = self.waitingTasks[machineType]
    local critical = self.server and self.server.taskScheduler and self.server.taskScheduler.currentCriticalMachine
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

function MachineScheduler:requestMachine(task)
    local machineType = task.machineType
    local machinesOfType = self.machinePool and self.machinePool:getMachines(machineType) or nil
    if machinesOfType then
        for _, machine in pairs(machinesOfType) do
            if not machine:isBusy() then
                return machine
            end
        end
    end
    if not task.queuedForMachine then
        self:enqueueTask(machineType, task)
        task.queuedForMachine = true
    end
    return nil
end

function MachineScheduler:notifyMachineFree(machineType)
    local queue = self.waitingTasks[machineType]
    if not queue or #queue == 0 then
        return
    end
    local machinesOfType = self.machinePool and self.machinePool:getMachines(machineType) or nil
    if not machinesOfType then
        return
    end
    for _, machine in pairs(machinesOfType) do
        if not machine:isBusy() then
            local task = table.remove(queue, 1)
            if task then
                task.queuedForMachine = false
                task:assignMachine(machine)
            end
            return
        end
    end
end

function MachineScheduler:logSaturation(machineType)
    local machinesOfType = self.machinePool and self.machinePool:getMachines(machineType) or nil
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
    if not self.server or not self.server.taskScheduler or not self.machinePool then
        return
    end
    local stats = self.server.taskScheduler:getMachineStats()
    self.logger.info("[planner] machines:")
    for machineType, entry in pairs(stats) do
        local total = self.machinePool:countMachines(machineType)
        local available = self.machinePool:countAvailableMachines(machineType)
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
    if not self.server or not self.server.taskScheduler or not self.machinePool then
        return
    end
    local stats = self.server.taskScheduler:getMachineStats()
    local critical = nil
    local criticalRatio = -1
    for machineType, entry in pairs(stats) do
        local count = self.machinePool:countMachines(machineType)
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
