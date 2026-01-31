local Object = require 'object.Object'
local Config = require 'inv.Config'
local CraftManager = require 'inv.CraftManager'
local DeviceManager = require 'inv.DeviceManager'
local InvManager = require 'inv.InvManager'
local StorageManager = require 'inv.StorageManager'
local Item = require 'inv.Item'
local TaskManager = require 'inv.TaskManager'

local Server = Object:subclass()

function Server:init()
    local deviceConfig, recipeConfig = self:loadConfig()
    self:setup(deviceConfig, recipeConfig)
    self:initCLI()
end

function Server:loadConfig()
    local configDir = "config/"
    local deviceConfig = Config.loadDirectory(configDir .. "devices")
    local recipeConfig = Config.loadDirectory(configDir .. "recipes")
    return deviceConfig, recipeConfig
end

function Server:setup(deviceConfig, recipeConfig)
    self.invManager = InvManager(self)
    self.storageManager = StorageManager(self)
    self.deviceManager = DeviceManager(self, deviceConfig)
    self.craftManager = CraftManager(self)
    self.taskManager = TaskManager(self)
    self.taskTimer = nil
    self.running = true

    self.craftManager:loadRecipes(recipeConfig)
    self.deviceManager:scanDevices()
end

function Server:handlePeripheralAttach(name)
    if peripheral.isPresent(name) then
        self.deviceManager:addDevice(name)
    end
end

function Server:handlePeripheralDetach(name)
    if not peripheral.isPresent(name) then
        self.deviceManager:removeDevice(name)
    end
end

function Server:initCLI()
    self.cliEnabled = true
    self.cliPrompt = "> "
    self.cliBuffer = ""
    self:drawPrompt()
    print("[cli] type 'help' for commands")
    self:drawPrompt()
end

function Server:drawPrompt()
    if not self.cliEnabled then
        return
    end
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.clearLine()
    write(self.cliPrompt .. self.cliBuffer)
end

function Server:cliOnChar(ch)
    self.cliBuffer = self.cliBuffer .. ch
    self:drawPrompt()
end

function Server:cliOnKey(key)
    if key == keys.backspace then
        if #self.cliBuffer > 0 then
            self.cliBuffer = self.cliBuffer:sub(1, -2)
        end
        self:drawPrompt()
        return
    end
    if key == keys.enter then
        local line = self.cliBuffer
        self.cliBuffer = ""
        local w, h = term.getSize()
        term.setCursorPos(1, h)
        term.clearLine()
        print(self.cliPrompt .. line)
        self:handleCommand(line)
        self:drawPrompt()
    end
end

function Server:handleCommand(line)
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
        print("commands:")
        print("  help")
        print("  list [filter]")
        print("  count <item>")
        print("  craft <item> <count>")
        print("  scan")
        print("  devices")
        print("  status")
        print("  quit")
        return
    end

    if cmd == "list" then
        local filter = args[2]
        if filter then
            filter = filter:lower()
        end
        local lines = {}
        for name, item in pairs(self.invManager.items) do
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
                print(line)
            end
        end
        return
    end

    if cmd == "count" then
        local name = args[2]
        if not name then
            print("usage: count <item>")
            return
        end
        local item = self.invManager.items[name]
        if item then
            print(name .. " x" .. tostring(item.count))
        else
            print(name .. " x0")
        end
        return
    end

    if cmd == "craft" then
        local name = args[2]
        local count = tonumber(args[3]) or 1
        if not name then
            print("usage: craft <item> <count>")
            return
        end
        local existing = self.invManager.items[name]
        local have = existing and existing.count or 0
        if have >= count then
            print("already have " .. tostring(have))
            return
        end
        local missing = count - have
        local planned = self.craftManager.planner:plan(Item{name=name, count=missing}, nil, nil)
        if planned == 0 then
            print("no recipe for " .. name)
        else
            print("planned " .. tostring(planned) .. " craft(s)")
        end
        return
    end

    if cmd == "scan" then
        self.invManager:scanInventories()
        print("inventories scanned")
        return
    end

    if cmd == "devices" then
        self.deviceManager:scanDevices()
        self.invManager:scanInventories()
        print("devices rescanned")
        return
    end

    if cmd == "status" then
        print("active tasks: " .. tostring(#self.taskManager.active))
        return
    end

    if cmd == "quit" or cmd == "exit" then
        self.running = false
        return
    end

    print("unknown command: " .. cmd)
end

function Server:handleEvent(evt)
    local event = evt[1]
    if event == "peripheral" then
        self:handlePeripheralAttach(evt[2])
    elseif event == "peripheral_detach" then
        self:handlePeripheralDetach(evt[2])
    elseif event == "terminate" then
        return false, false
    elseif event == "char" then
        self:cliOnChar(evt[2])
    elseif event == "key" then
        self:cliOnKey(evt[2])
    end

    local runTasks = true
    if event == "timer" and evt[2] ~= self.taskTimer then
        runTasks = false
    end

    return true, runTasks
end

function Server:updateTasks()
    if self.taskManager:update() then
        self.taskTimer = os.startTimer(1)
        print("[server] active tasks:", #self.taskManager.active)
        --for i,t in pairs(self.taskManager.sleeping) do
        --    print("sleeping",i)
        --end
        --print(math.random(1,100))
    end
end

function Server:broadcastUpdatedItems()
    self.invManager:getUpdatedItems()
end

function Server:mainLoop()
    while self.running do
        local evt = {os.pullEventRaw()}
        local shouldContinue, runTasks = self:handleEvent(evt)
        if not shouldContinue then
            break
        end
        if runTasks then
            self:updateTasks()
        end
        self:broadcastUpdatedItems()
        self:drawPrompt()
    end
end

return Server
