local Class = require 'inv.core.Class'
local CraftTask = require 'inv.domain.CraftTask'

-- Asynchronously manages crafting tasks
local TaskScheduler = Class:subclass()

function TaskScheduler:init(server)
    self.server = server
    self.logger = server.logger
    -- table<int, Task>: Tasks that are currently performing an operation,
    -- e.g. counting and storing output items from a crafting machine.
    self.active = {}
    -- table<int, Task>: Tasks that are waiting for another task to complete.
    -- Indexed by task ID.
    self.sleeping = {}
    -- The last ID assigned to a task.
    self.lastID = 0
    self.summaries = {}
    self.nextSummaryId = 0
    self.currentCriticalMachine = nil
    self.currentRunId = nil
    self.executions = {}
end

-- Returns the next available task ID for creating a new task.
function TaskScheduler:nextID()
    self.lastID = self.lastID + 1
    return self.lastID
end

function TaskScheduler:ensureTaskId(task)
    if not task.id then
        task.id = self:nextID()
    end
end

local function isCraftTask(task)
    return task and task.instanceof and task:instanceof(CraftTask)
end

local function blockedByForMissing(missing)
    local blocker = missing and missing[1] or nil
    if not blocker then
        return nil
    end
    if blocker.reason then
        return blocker.reason
    end
    if blocker.name then
        return blocker.name
    end
    if blocker.tags then
        for tag, _ in pairs(blocker.tags) do
            return "tag:" .. tag
        end
    end
    return nil
end

local function waitItemKey(item)
    if not item then
        return nil
    end
    if item.name then
        return item.name
    end
    if item.tags then
        for tag, _ in pairs(item.tags) do
            return "tag:" .. tag
        end
    end
    return nil
end

local function isWaitTask(task)
    return task and task.waitItem ~= nil
end

function TaskScheduler:getExecution(task)
    local exec = self.executions[task.id]
    if not exec then
        exec = {machine=nil, session=nil}
        self.executions[task.id] = exec
    end
    return exec
end

function TaskScheduler:runWaitTask(task)
    local missing = self.server.inventoryQuery:tryMatchAll({task.waitItem})
    if #missing == 0 then
        return "done"
    end
    self:recordWaitProgress(task)
    self:setStatus(task, "blocked", "inputs", waitItemKey(task.waitItem))
    if task.waitReason then
        self.logger.cli("[task] waiting on items " .. tostring(task.waitReason))
    end
    return nil
end

function TaskScheduler:clearExecution(task)
    self.executions[task.id] = nil
end

function TaskScheduler:runCraftTask(task)
    if task.retryAfter and os.clock() < task.retryAfter then
        self:recordWaitProgress(task)
        return nil
    end

    local exec = self:getExecution(task)

    if exec.session then
        local ok, code = exec.session:drainOutput()
        if not ok then
            task.state = "failed"
            self:setStatus(task, "failed", code)
            self.logger.warn("[task] failed", code, "on", exec.machine and exec.machine.name or "unknown")
            local endAt = os.clock()
            local runSeconds = task.startedAt and (endAt - task.startedAt) or 0
            if task.summaryId then
                self:recordTaskComplete(task.summaryId, task.machineType, runSeconds)
            end
            exec.session:close()
            exec.session = nil
            exec.machine = nil
            self.server.machineScheduler:notifyMachineFree(task.machineType)
            return "failed"
        end
        if exec.session:isDone() or (exec.machine and exec.machine:isFinished()) then
            local endAt = os.clock()
            local runSeconds = task.startedAt and (endAt - task.startedAt) or 0
            local totalSeconds = endAt - task.createdAt
            if task.summaryId then
                self:recordTaskComplete(task.summaryId, task.machineType, runSeconds)
            end
            self.logger.debug(
                "[task] completed",
                task.recipe.machine,
                "x" .. tostring(task.craftCount),
                "on",
                exec.machine and exec.machine.name or "unknown",
                "run",
                string.format("%.2fs", runSeconds),
                "total",
                string.format("%.2fs", totalSeconds)
            )
            exec.session = nil
            exec.machine = nil
            task.state = "done"
            self:setStatus(task, "done")
            self.server.machineScheduler:notifyMachineFree(task.machineType)
            return "done"
        end
        task.state = "running"
        self:setStatus(task, "running")
        return nil
    end

    if task:wantsInputs() then
        local missing = self.server.inventoryQuery:tryMatchAll(task:scaledInputs())
        if #missing > 0 then
            local blockedBy = blockedByForMissing(missing)
            if task.needsDependencies and self.server.craftExecutor and self.server.craftExecutor.taskGraphBuilder then
                task.needsDependencies = false
                self.server.craftExecutor.taskGraphBuilder:link(task, task.recipe, 0, {}, task.craftCount, task.summaryId)
            end
            task.state = "waiting_inputs"
            self:setStatus(task, "blocked", "inputs", blockedBy)
            self:recordWaitProgress(task)
            return nil
        end
        if task.state == "waiting_inputs" then
            task.state = "waiting_machine"
        end
    end

    if not task:wantsMachine() then
        return nil
    end

    local machine = self.server.machineScheduler:requestMachine(task)
    if not machine then
        task.state = "waiting_machine"
        self:setStatus(task, "waiting", "machine")
        self.server.machineScheduler:logSaturation(task.recipe.machine)
        self:recordWaitProgress(task)
        return nil
    end

    task.retryAfter = nil
    exec.machine = machine
    task:bindMachine(machine)

    local session = machine:createSession(task.recipe, task.dest, task.destSlot, task.craftCount)
    if not session then
        exec.machine = nil
        task:onStartFailure("machine")
        self:setStatus(task, "waiting", "machine")
        return nil
    end
    exec.session = session

    local ok, code = session:prepareInputs()
    if not ok then
        session:close()
        exec.session = nil
        exec.machine = nil
        task:onStartFailure("inputs")
        self:setStatus(task, "blocked", "inputs")
        self:recordWaitProgress(task)
        return nil
    end

    session:startCraft()
    local blocker = task.blockedBy
    task:startExecution()
    task:onStartSuccess()
    self:setStatus(task, "running")
    local waitSeconds = task.startedAt - task.createdAt
    if task.summaryId then
        self:recordTaskStart(task.summaryId, task.machineType, waitSeconds)
    end
    self.logger.debug(
        "[task] start",
        task.recipe.machine,
        "x" .. tostring(task.craftCount),
        "reason: inputs_ready",
        "waited",
        string.format("%.2fs", waitSeconds),
        blocker and ("blocked_by " .. blocker) or ""
    )
    return nil
end

-- Updates all running tasks, sleeping parent tasks when they create sub-tasks
-- and resuming them when the sub-tasks complete.
function TaskScheduler:tick()
    --print("calling update")
    local i = 1
    while i <= #self.active do
        local task = self.active[i]
        local result = nil
        if isCraftTask(task) then
            result = self:runCraftTask(task)
        elseif isWaitTask(task) then
            result = self:runWaitTask(task)
        else
            if task:run() then
                result = "done"
            end
        end
        if result then
            table.remove(self.active, i)
            local parent = task.parent
            if not isCraftTask(task) then
                if result == "failed" then
                    self:setStatus(task, "failed")
                else
                    self:setStatus(task, "done")
                end
            end
            task:destroy()
            if parent then
                parent:onChildDone(task)
            end
            if isCraftTask(task) then
                self:clearExecution(task)
            end
            if parent and parent.nSubTasks == 0 then
                self.sleeping[parent.id] = nil
                table.insert(self.active, parent)
                self:setStatus(parent, "ready")
            end
        elseif task.nSubTasks > 0 then
            table.remove(self.active, i)
            self.sleeping[task.id] = task
            self:setStatus(task, "waiting", "subtasks")
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
function TaskScheduler:addTask(task)
    self:ensureTaskId(task)
    if task.parent then
        self:ensureTaskId(task.parent)
        task:attachToParent()
    end
    if isWaitTask(task) then
        table.insert(self.active, task)
        self:setStatus(task, "blocked", "inputs", waitItemKey(task.waitItem))
        return
    end
    if task.nSubTasks and task.nSubTasks > 0 then
        self.sleeping[task.id] = task
        self:setStatus(task, "waiting", "subtasks")
    else
        table.insert(self.active, task)
        self:setStatus(task, "ready")
    end
end

function TaskScheduler:createSummary(criteria, crafts)
    self.nextSummaryId = self.nextSummaryId + 1
    local name = criteria and (criteria.name or "unknown") or "unknown"
    local count = criteria and criteria.count or crafts or 0
    local summary = {
        id = self.nextSummaryId,
        name = name,
        count = count,
        startTime = os.clock(),
        firstTaskStartedAt = nil,
        criticalPathStartedAt = nil,
        tasksTotal = 0,
        tasksDone = 0,
        machineStats = {},
        inputBlockers = {},
        runId = self.currentRunId
    }
    self.summaries[summary.id] = summary
    return summary
end

function TaskScheduler:registerTask(summary, task)
    if not summary then
        return
    end
    summary.tasksTotal = summary.tasksTotal + 1
    task.summaryId = summary.id
end

local function waitReasonForTask(task)
    if task.status == "waiting" and task.statusReason == "machine" then
        return "waiting_machine"
    end
    if task.status == "blocked" and task.statusReason == "inputs" then
        return "waiting_inputs"
    end
    return nil
end

function TaskScheduler:recordWaitProgress(task)
    if not task or not task.summaryId or not task.machineType then
        return
    end
    local reason = waitReasonForTask(task)
    if not reason then
        return
    end
    local now = os.clock()
    local waited = now - (task.lastStatusAt or now)
    if waited <= 0 then
        return
    end
    self:recordWait(task.summaryId, task.machineType, reason, waited)
    if reason == "waiting_inputs" and task.blockedBy then
        self:recordInputBlocker(task.summaryId, task.machineType, task.blockedBy, waited)
    end
    task.lastStatusAt = now
end

function TaskScheduler:setStatus(task, newStatus, reason, blockedBy)
    if not task then
        return
    end
    if task.status == newStatus and task.statusReason == reason and task.blockedBy == blockedBy then
        return
    end
    local prevStatus = task.status
    local prevReason = task.statusReason
    if task.summaryId then
        self:recordWaitProgress(task)
        if prevStatus == "blocked" and prevReason == "inputs" then
            task.blockedBy = nil
        end
    end
    task:setStatus(newStatus, reason, nil, blockedBy)
end

local function getMachineEntry(summary, machineType)
    local entry = summary.machineStats[machineType]
    if not entry then
        entry = {
            waitSum=0,
            waitCount=0,
            waitMax=0,
            waitMachineSum=0,
            waitMachineCount=0,
            waitMachineMax=0,
            waitInputsSum=0,
            waitInputsCount=0,
            waitInputsMax=0,
            runSum=0
        }
        summary.machineStats[machineType] = entry
    end
    return entry
end

function TaskScheduler:recordTaskStart(summaryId, machineType, waitSeconds)
    local summary = summaryId and self.summaries[summaryId] or nil
    if not summary then
        return
    end
    if not summary.firstTaskStartedAt then
        summary.firstTaskStartedAt = os.clock()
        self.logger.info("[phase] first_task_started at +" .. string.format("%.2fs", summary.firstTaskStartedAt - summary.startTime))
    end
    if summary.criticalPathStartedAt == nil and self.currentCriticalMachine == machineType then
        summary.criticalPathStartedAt = os.clock()
        self.logger.info("[phase] critical_path_started at +" .. string.format("%.2fs", summary.criticalPathStartedAt - summary.startTime))
    end
    local entry = getMachineEntry(summary, machineType)
    entry.waitSum = entry.waitSum + waitSeconds
    entry.waitCount = entry.waitCount + 1
    if waitSeconds > entry.waitMax then
        entry.waitMax = waitSeconds
    end
end

function TaskScheduler:recordWait(summaryId, machineType, reason, waitSeconds)
    local summary = summaryId and self.summaries[summaryId] or nil
    if not summary then
        return
    end
    local entry = getMachineEntry(summary, machineType)
    if reason == "waiting_machine" then
        entry.waitMachineSum = entry.waitMachineSum + waitSeconds
        entry.waitMachineCount = entry.waitMachineCount + 1
        if waitSeconds > entry.waitMachineMax then
            entry.waitMachineMax = waitSeconds
        end
    elseif reason == "waiting_inputs" then
        entry.waitInputsSum = entry.waitInputsSum + waitSeconds
        entry.waitInputsCount = entry.waitInputsCount + 1
        if waitSeconds > entry.waitInputsMax then
            entry.waitInputsMax = waitSeconds
        end
    end
end

function TaskScheduler:recordInputBlocker(summaryId, machineType, itemName, waitSeconds)
    local summary = summaryId and self.summaries[summaryId] or nil
    if not summary or not itemName then
        return
    end
    summary.inputBlockers[machineType] = summary.inputBlockers[machineType] or {}
    local entry = summary.inputBlockers[machineType][itemName]
    if not entry then
        entry = {sum=0, max=0}
        summary.inputBlockers[machineType][itemName] = entry
    end
    entry.sum = entry.sum + waitSeconds
    if waitSeconds > entry.max then
        entry.max = waitSeconds
    end
end

function TaskScheduler:recordTaskComplete(summaryId, machineType, runSeconds)
    local summary = summaryId and self.summaries[summaryId] or nil
    if not summary then
        return
    end
    local entry = getMachineEntry(summary, machineType)
    entry.runSum = entry.runSum + runSeconds
    summary.tasksDone = summary.tasksDone + 1
    if summary.tasksDone >= summary.tasksTotal then
        self:logSummary(summary)
        self.summaries[summary.id] = nil
    end
end

function TaskScheduler:logSummary(summary)
    local totalTime = os.clock() - summary.startTime
    local machineRegistry = self.server and self.server.machineRegistry or nil
    local criticalMachine = nil
    local criticalUtil = -1
    local theoreticalMin = 0
    local totalWaitInputs = 0
    local totalWaitMachine = 0
    local totalRun = 0
    for machineType, entry in pairs(summary.machineStats) do
        local count = machineRegistry and machineRegistry:countMachines(machineType) or 0
        if count > 0 then
            local util = (entry.runSum / (totalTime * count)) * 100
            if util > criticalUtil then
                criticalUtil = util
                criticalMachine = machineType
            end
            local minTime = entry.runSum / count
            if minTime > theoreticalMin then
                theoreticalMin = minTime
            end
        end
        totalWaitInputs = totalWaitInputs + entry.waitInputsSum
        totalWaitMachine = totalWaitMachine + entry.waitMachineSum
        totalRun = totalRun + entry.runSum
    end
    local overhead = totalTime - theoreticalMin
    if overhead < 0 then
        overhead = 0
    end
    local overheadPct = totalTime > 0 and (overhead / totalTime) * 100 or 0
    local lostTotal = totalWaitInputs + totalWaitMachine
    local idle = totalTime - (totalRun / math.max(1, (criticalMachine and machineRegistry:countMachines(criticalMachine) or 1)))
    if idle < 0 then
        idle = 0
    end
    self.logger.info("[summary] craft", summary.name, "x" .. tostring(summary.count))
    self.logger.info("  total_time:", string.format("%.2fs", totalTime))
    if criticalMachine then
        self.logger.info("  critical_machine:", criticalMachine)
    end
    if theoreticalMin > 0 then
        self.logger.info("  theoretical_min:", string.format("%.2fs", theoreticalMin))
        local efficiency = (theoreticalMin / totalTime) * 100
        self.logger.info("  efficiency:", string.format("%.0f%%", efficiency))
        self.logger.info("  overhead:", "+" .. string.format("%.2fs", overhead), "(" .. string.format("%.0f%%", overheadPct) .. ")")
    end
    self.logger.info("  utilization:")
    for machineType, entry in pairs(summary.machineStats) do
        local count = machineRegistry and machineRegistry:countMachines(machineType) or 0
        local util = (count > 0 and totalTime > 0) and (entry.runSum / (totalTime * count)) * 100 or 0
        self.logger.info("    " .. machineType .. ":", string.format("%.0f%%", util))
    end
    self.logger.info("  waits:")
    for machineType, entry in pairs(summary.machineStats) do
        local avgWait = entry.waitCount > 0 and (entry.waitSum / entry.waitCount) or 0
        self.logger.info(
            "    " .. machineType .. ":",
            "avg " .. string.format("%.2fs", avgWait) .. ",",
            "max " .. string.format("%.2fs", entry.waitMax)
        )
    end
    self.logger.info("  wait_reasons: (inputs = not in storage, machine = no free machine)")
    for machineType, entry in pairs(summary.machineStats) do
        local avgMachine = entry.waitMachineCount > 0 and (entry.waitMachineSum / entry.waitMachineCount) or 0
        local avgInputs = entry.waitInputsCount > 0 and (entry.waitInputsSum / entry.waitInputsCount) or 0
        self.logger.info(
            "    " .. machineType .. ":",
            "machine avg " .. string.format("%.2fs", avgMachine) .. ",",
            "max " .. string.format("%.2fs", entry.waitMachineMax) .. ";",
            "inputs avg " .. string.format("%.2fs", avgInputs) .. ",",
            "max " .. string.format("%.2fs", entry.waitInputsMax)
        )
    end
    self.logger.info("  lost_time:")
    if lostTotal > 0 then
        self.logger.info("    waiting_inputs:", string.format("%.0f%%", (totalWaitInputs / lostTotal) * 100))
        self.logger.info("    waiting_machine:", string.format("%.0f%%", (totalWaitMachine / lostTotal) * 100))
        local idlePct = totalTime > 0 and (idle / totalTime) * 100 or 0
        self.logger.info("    idle:", string.format("%.0f%%", idlePct))
    end
    self.logger.info("  input_blockers:")
    for machineType, items in pairs(summary.inputBlockers) do
        local topName = nil
        local topSum = -1
        local topMax = 0
        for name, entry in pairs(items) do
            if entry.sum > topSum then
                topSum = entry.sum
                topMax = entry.max
                topName = name
            end
        end
        if topName then
            local impactPct = totalTime > 0 and (topSum / totalTime) * 100 or 0
            self.logger.info("    " .. machineType .. ":")
            self.logger.info("      primary_blocker:", topName)
            self.logger.info("      impact:", string.format("%.2fs", topSum), "(" .. string.format("%.0f%%", impactPct) .. ")")
        end
    end
    if criticalMachine and machineRegistry then
        local count = machineRegistry:countMachines(criticalMachine)
        if count > 0 then
            local criticalEntry = summary.machineStats[criticalMachine]
            local waitMachine = criticalEntry and criticalEntry.waitMachineSum or 0
            local waitInputs = criticalEntry and criticalEntry.waitInputsSum or 0
            if waitMachine > waitInputs then
                local newMin = criticalEntry and (criticalEntry.runSum / (count + 1)) or 0
                if newMin > 0 then
                    self.logger.info("[hint] bottleneck detected:", criticalMachine)
                    self.logger.info("[hint] adding +1 machine reduces theoretical_min to", string.format("%.2fs", newMin))
                end
            end
        end
    end
    if summary.runId then
        self.logger.info("[run] id=" .. summary.runId .. " completed in " .. string.format("%.2fs", totalTime))
    end
end

function TaskScheduler:getMachineStats()
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
        if task.status == "blocked" and task.statusReason == "inputs" then
            entry.waiting_inputs = entry.waiting_inputs + 1
        elseif task.status == "waiting" and task.statusReason == "machine" then
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

return TaskScheduler



