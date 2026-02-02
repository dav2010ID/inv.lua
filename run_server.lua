local Server = require 'inv.Server'
local Log = require 'inv.Log'

local args = {...}

local function initLogging(path)
    local log = fs.open(path, "a")
    if not log then
        return
    end
    local oldPrint = print
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        local line = table.concat(parts, " ")
        oldPrint(line)
        log.writeLine(line)
        log.flush()
    end
end

function run()
    initLogging("CraftOSTest.log")
    Log.setLevel("debug")
    local runId = os.date("!%Y-%m-%dT%H:%MZ")
    Log.info("[run] id=" .. runId, "goal=" .. table.concat(args, " "))
    Log.runId = runId
    local s = Server()
    if #args > 0 then
        local command = table.concat(args, " ")
        Log.info("executing CLI command:", command)
        s.cliEnabled = false
        s.cliBuffer = ""
        s:handleCommand(command)
        s.cliEnabled = true
        s:drawPrompt()
    end
    s:mainLoop()
end

run()

--local ok, res = xpcall(run, debug.traceback)
--textutils.pagedPrint(res)
