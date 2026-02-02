local Object = require 'inv.core.Object'
local Item = require 'inv.domain.Item'

local CliController = Object:subclass()

function CliController:init(server)
    self.server = server
    self.logger = server.logger
    self.enabled = true
    self.prompt = "> "
    self.buffer = ""
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
        for name, item in pairs(self.server.inventoryService:getItems()) do
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
        local count = self.server.inventoryService:getItemCount(name)
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
        local have = self.server.inventoryService:getItemCount(name)
        if have >= count then
            self.logger.cli("already have " .. tostring(have))
            return
        end
        local missing = count - have
        local plan = self.server.craftExecutor.planner:plan(Item{name=name, count=missing})
        if not plan then
            self.logger.warn("no recipe for", name)
        else
            self.server.craftExecutor.factory:queuePlan(plan, nil, nil)
            self.logger.info("planned", plan.crafts, "craft(s)")
        end
        return
    end

    if cmd == "scan" then
        self.server.inventoryService:scanInventories()
        self.logger.info("inventories scanned")
        return
    end

    if cmd == "devices" then
        self.server.deviceCatalog:scanDevices()
        self.server.inventoryService:scanInventories()
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

return CliController

