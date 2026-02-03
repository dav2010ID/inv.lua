local Class = require 'inv.core.Class'
local Item = require 'inv.domain.Item'
local Config = require 'inv.infrastructure.Config'

local CliController = Class:subclass()

function CliController:init(server)
    self.server = server
    self.logger = server.logger
    self.enabled = true
    self.prompt = "> "
    self.buffer = ""
    self.recipeCapture = nil
    self:drawPrompt()
    self.logger.cli("[cli] type 'help' for commands")
    self:drawPrompt()
end

function CliController:setEnabled(enabled)
    self.enabled = enabled and true or false
end

function CliController:clearBuffer()
    self.buffer = ""
end

function CliController:drawPrompt()
    if not self.enabled then
        return
    end
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.clearLine()
    write(self.prompt .. self.buffer)
end

function CliController:onChar(ch)
    self.buffer = self.buffer .. ch
    self:drawPrompt()
end

function CliController:onKey(key)
    if key == keys.backspace then
        if #self.buffer > 0 then
            self.buffer = self.buffer:sub(1, -2)
        end
        self:drawPrompt()
        return
    end
    if key == keys.enter then
        local line = self.buffer
        self.buffer = ""
        local w, h = term.getSize()
        term.setCursorPos(1, h)
        term.clearLine()
        self.logger.cli(self.prompt .. line)
        self:handleCommand(line)
        self:drawPrompt()
    end
end

function CliController:handleCommand(line)
    local args = {}
    for token in string.gmatch(line, "%S+") do
        table.insert(args, token)
    end
    local cmd = args[1]
    if not cmd then
        return
    end
    cmd = cmd:lower()

    if cmd == "help" then
        self.logger.cli("commands:")
        self.logger.cli("  help")
        self.logger.cli("  list [filter]")
        self.logger.cli("  count <item>")
        self.logger.cli("  craft <item> <count>")
        self.logger.cli("  new <machine>")
        self.logger.cli("  ok")
        self.logger.cli("  scan")
        self.logger.cli("  devices")
        self.logger.cli("  peripherals")
        self.logger.cli("  status")
        self.logger.cli("  quit")
        self.logger.cli("  test")
        return
    end

    if cmd == "list" then
        local filter = args[2]
        if filter then
            filter = filter:lower()
        end
        local lines = {}
        for name, item in pairs(self.server.inventoryQuery:getItems()) do
            local label = item:getName()
            if not filter
                or name:lower():find(filter, 1, true)
                or (label and label:lower():find(filter, 1, true)) then
                table.insert(lines, string.format("%s x%d", label, item.count))
            end
        end
        table.sort(lines)
        if textutils and textutils.pagedPrint then
            textutils.pagedPrint(table.concat(lines, "\n"))
        else
            for i, line in ipairs(lines) do
                self.logger.cli(line)
            end
        end
        return
    end

    if cmd == "count" then
        local name = args[2]
        if not name then
            self.logger.cli("usage: count <item>")
            return
        end
        local count = self.server.inventoryQuery:getItemCount(name)
        self.logger.cli(name .. " x" .. tostring(count))
        return
    end

    if cmd == "craft" then
        local name = args[2]
        local count = tonumber(args[3]) or 1
        if not name then
            self.logger.cli("usage: craft <item> <count>")
            return
        end
        local have = self.server.inventoryQuery:getItemCount(name)
        if have >= count then
            self.logger.cli("already have " .. tostring(have))
            return
        end
        local missing = count - have
        local plan = self.server.craftExecutor.planner:plan(Item{name=name, count=missing})
        if not plan then
            self.logger.warn("no recipe for", name)
        else
            self.server.craftExecutor.taskQueue:queuePlan(plan, nil, nil)
            self.logger.info("planned", plan.crafts, "craft(s)")
        end
        return
    end

    if cmd == "new" then
        local machineId = args[2]
        if not machineId then
            self.logger.cli("usage: new <machine>")
            return
        end
        if self.recipeCapture then
            self.logger.cli("recipe capture already in progress; type 'ok' when ready")
            return
        end
        local machine = self:findMachine(machineId)
        if not machine then
            self.logger.warn("unknown machine:", machineId)
            return
        end
        self.recipeCapture = {
            machineType = machine.type,
            machineName = machine.name,
            machine = machine,
            step = "await_inputs",
            createdAt = os.clock()
        }
        self.logger.cli("put ingredients into machine, then type 'ok'")
        return
    end

    if cmd == "ok" then
        if not self.recipeCapture then
            self.logger.cli("no recipe capture in progress")
            return
        end
        if self.recipeCapture.step == "await_inputs" then
            local ok, err = self:recordRecipeInputs(self.recipeCapture)
            if not ok then
                if err then
                    self.logger.warn(err)
                else
                    self.logger.warn("failed to record inputs")
                end
                return
            end
            self.logger.cli("inputs recorded, waiting for output...")
            return
        end
        if self.recipeCapture.step == "await_output" then
            self.logger.cli("waiting for output; please wait")
            return
        end
        if self.recipeCapture.step == "await_confirm" then
            local ok, err = self:finalizeRecipe(self.recipeCapture, self.recipeCapture.pendingOutput)
            if ok then
                self.logger.cli("recipe saved")
            else
                if err then
                    self.logger.warn(err)
                end
            end
            self.recipeCapture = nil
            return
        end
        self.logger.cli("recipe capture in unknown state")
        return
    end

    if cmd == "scan" then
        self.server.inventoryMutator:scanInventories()
        self.logger.info("inventories scanned")
        return
    end

    if cmd == "devices" then
        self.server.deviceCatalog:scanDevices()
        self.server.inventoryMutator:scanInventories()
        self.logger.info("devices rescanned")
        return
    end

    if cmd == "peripherals" then
        local lines = {}
        for _, name in ipairs(peripheral.getNames()) do
            local device = self.server.deviceCatalog.devices[name]
            local kind = (device and device.type) or peripheral.getType(name) or "unknown"
            local purpose = "unknown"
            if device and device.config and device.config.purpose then
                purpose = device.config.purpose
            end
            table.insert(lines, string.format("%s | type=%s | purpose=%s", name, kind, purpose))
        end
        table.sort(lines)
        if #lines == 0 then
            self.logger.cli("no peripherals")
        else
            for _, line in ipairs(lines) do
                self.logger.cli(line)
            end
        end
        return
    end

    if cmd == "status" then
        self.logger.info("active tasks:", #self.server.taskScheduler.active)
        return
    end

    if cmd == "quit" or cmd == "exit" then
        if self.server.runtime then
            self.server.runtime:stop()
        end
        return
    end

    self.logger.warn("unknown command:", cmd)
end

function CliController:findMachine(machineId)
    local registry = self.server.machineRegistry
    if not registry or not machineId then
        return nil
    end
    local byType = registry:getAny(machineId)
    if byType then
        return byType
    end
    for _, machines in pairs(registry.machines or {}) do
        if machines[machineId] then
            return machines[machineId]
        end
    end
    return nil
end

function CliController:virtualSlotForReal(machine, realSlot)
    if machine.useIdentitySlots then
        return realSlot
    end
    for virtSlot, mapped in pairs(machine.slots or {}) do
        if mapped == realSlot then
            return virtSlot
        end
    end
    return realSlot
end

function CliController:snapshotMachine(machine)
    local snapshot = {}
    local items = machine:list()
    for realSlot, item in pairs(items) do
        local virtSlot = self:virtualSlotForReal(machine, realSlot)
        if virtSlot then
            local detail = machine:getItemDetail(realSlot)
            if detail then
                snapshot[virtSlot] = detail
            else
                snapshot[virtSlot] = {name=item.name, count=item.count}
            end
        end
    end
    return snapshot
end

local function toItemSpec(detail, countOverride)
    if not detail or not detail.name then
        return nil
    end
    local spec = {
        name = detail.name,
        count = countOverride or detail.count or 1
    }
    if detail.tags then
        spec.tags = detail.tags
    end
    return spec
end

function CliController:buildRecipeInput(snapshot, outputVirtSlot)
    local input = {}
    for virtSlot, detail in pairs(snapshot) do
        if virtSlot ~= outputVirtSlot and detail and detail.count and detail.count > 0 then
            local spec = toItemSpec(detail)
            if spec then
                input[tostring(virtSlot)] = spec
            end
        end
    end
    return input
end

function CliController:computeOutputDelta(before, after)
    local output = {}
    for virtSlot, detail in pairs(after) do
        if detail and detail.count and detail.count > 0 then
            local prev = before and before[virtSlot] or nil
            if prev and prev.name == detail.name then
                local delta = (detail.count or 0) - (prev.count or 0)
                if delta > 0 then
                    local spec = toItemSpec(detail, delta)
                    if spec then
                        output[tostring(virtSlot)] = spec
                    end
                end
            else
                local spec = toItemSpec(detail)
                if spec then
                    output[tostring(virtSlot)] = spec
                end
            end
        end
    end
    return output
end

function CliController:recordRecipeInputs(state)
    local machine = state.machine
    if not machine then
        return false, "machine not found"
    end
    local outputVirt = machine.craftOutputSlot or 10
    local ok, outputReal = pcall(function()
        return machine:getCraftOutputSlot()
    end)
    if not ok or not outputReal then
        return false, "output slot mapping missing"
    end
    local snapshot = self:snapshotMachine(machine)
    local input = self:buildRecipeInput(snapshot, outputVirt)
    if not next(input) then
        return false, "no inputs detected"
    end
    state.step = "await_output"
    state.input = input
    state.before = snapshot
    state.outputVirt = outputVirt
    state.startedAt = os.clock()
    state.pendingOutput = nil
    state.outputDetectedAt = nil
    return true
end

function CliController:appendRecipeToFile(spec)
    local dir = Config.convertPath("config/recipes")
    local filename = dir .. "/user.json"
    local entries = {}
    if fs.exists(filename) then
        local file = io.open(filename, "r")
        if file then
            local data = file:read("*all")
            file:close()
            local ok, parsed = pcall(textutils.unserialiseJSON, data)
            if ok and parsed then
                if parsed[1] then
                    entries = parsed
                else
                    entries = {parsed}
                end
            end
        end
    end
    table.insert(entries, spec)
    local out = io.open(filename, "w")
    assert(out, "failed to open recipe file for write")
    out:write(textutils.serialiseJSON(entries))
    out:close()
end

function CliController:finalizeRecipe(state, output)
    if not output or not next(output) then
        return false, "no output detected yet"
    end
    local spec = {
        machine = state.machineType,
        input = state.input,
        output = output
    }
    self.server.recipeStore:loadRecipes({spec})
    self:appendRecipeToFile(spec)
    local firstOut = nil
    for _, v in pairs(output) do
        firstOut = v.name
        break
    end
    self.logger.info("[craft] added recipe", firstOut or "unknown")
    return true
end

function CliController:tick()
    if not self.recipeCapture or self.recipeCapture.step ~= "await_output" then
        return
    end
    local machine = self.recipeCapture.machine
    if not machine then
        self.logger.warn("recipe capture failed: machine missing")
        self.recipeCapture = nil
        return
    end
    local after = self:snapshotMachine(machine)
    local output = self:computeOutputDelta(self.recipeCapture.before, after)
    if output and next(output) then
        self.recipeCapture.pendingOutput = output
        self.recipeCapture.outputDetectedAt = os.clock()
        self.recipeCapture.step = "await_confirm"
        self.logger.cli("output detected; type 'ok' to save recipe")
    end
end

return CliController



