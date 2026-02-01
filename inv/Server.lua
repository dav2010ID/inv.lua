local Object = require 'object.Object'
local Config = require 'inv.Config'
local CraftRegistry = require 'inv.CraftRegistry'
local CraftExecutor = require 'inv.CraftExecutor'
local DeviceManager = require 'inv.DeviceManager'
local InventoryIndex = require 'inv.InventoryIndex'
local InventoryIO = require 'inv.InventoryIO'
local StorageManager = require 'inv.StorageManager'
local Item = require 'inv.Item'
local TaskManager = require 'inv.TaskManager'
local Log = require 'inv.Log'

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
    self.inventoryIndex = InventoryIndex(self)
    self.inventoryIO = InventoryIO(self, self.inventoryIndex)
    self.storageManager = StorageManager(self)
    self.deviceManager = DeviceManager(self, deviceConfig)
    self.craftRegistry = CraftRegistry(self)
    self.craftExecutor = CraftExecutor(self, self.craftRegistry)
    self.taskManager = TaskManager(self)
    if Log and Log.runId then
        self.taskManager.currentRunId = Log.runId
    end
    self.taskTimer = nil
    self.running = true
    self.lastActiveCount = nil
    self.lastActiveLogTime = 0

    self.craftRegistry:loadRecipes(recipeConfig)
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
    Log.cli("[cli] type 'help' for commands")
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
        Log.cli(self.cliPrompt .. line)
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
        Log.cli("commands:")
        Log.cli("  help")
        Log.cli("  list [filter]")
        Log.cli("  count <item>")
        Log.cli("  craft <item> <count>")
        Log.cli("  scan")
        Log.cli("  devices")
        Log.cli("  status")
        Log.cli("  quit")
        Log.cli("  test")
        return
    end

    if cmd == "list" then
        local filter = args[2]
        if filter then
            filter = filter:lower()
        end
        local lines = {}
        for name, item in pairs(self.inventoryIndex.items) do
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
                Log.cli(line)
            end
        end
        return
    end

    if cmd == "count" then
        local name = args[2]
        if not name then
            Log.cli("usage: count <item>")
            return
        end
        local item = self.inventoryIndex.items[name]
        if item then
            Log.cli(name .. " x" .. tostring(item.count))
        else
            Log.cli(name .. " x0")
        end
        return
    end

    if cmd == "craft" then
        local name = args[2]
        local count = tonumber(args[3]) or 1
        if not name then
            Log.cli("usage: craft <item> <count>")
            return
        end
        local existing = self.inventoryIndex.items[name]
        local have = existing and existing.count or 0
        if have >= count then
            Log.cli("already have " .. tostring(have))
            return
        end
        local missing = count - have
        local planned = self.craftExecutor.planner:plan(Item{name=name, count=missing}, nil, nil)
        if planned == 0 then
            Log.warn("no recipe for", name)
        else
            Log.info("planned", planned, "craft(s)")
        end
        return
    end

    if cmd == "scan" then
        self.inventoryIO:scanInventories()
        Log.info("inventories scanned")
        return
    end

    if cmd == "devices" then
        self.deviceManager:scanDevices()
        self.inventoryIO:scanInventories()
        Log.info("devices rescanned")
        return
    end

    if cmd == "status" then
        Log.info("active tasks:", #self.taskManager.active)
        return
    end

    if cmd == "quit" or cmd == "exit" then
        self.running = false
        return
    end

    Log.warn("unknown command:", cmd)
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
        local activeCount = #self.taskManager.active
        local now = os.clock()
        if self.lastActiveCount ~= activeCount or (now - self.lastActiveLogTime) > 5 then
            Log.info("[server] active tasks:", activeCount)
            self.lastActiveCount = activeCount
            self.lastActiveLogTime = now
        end
        --for i,t in pairs(self.taskManager.sleeping) do
        --    print("sleeping",i)
        --end
        --print(math.random(1,100))
    end
end

function Server:broadcastUpdatedItems()
    self.inventoryIndex:getUpdatedItems()
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
