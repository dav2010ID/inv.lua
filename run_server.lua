local Server = require 'inv.runtime.Server'
local Logger = require 'inv.infrastructure.Log'

local args = {...}

local function initLogging(path, maxSize)
    maxSize = 100 * 1024  -- 100 KB
    local oldPrint = print

    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        local line = table.concat(parts, " ")

        oldPrint(line)

        if fs.exists(path) and fs.getSize(path) > maxSize then
            fs.delete(path)
        end

        local log = fs.open(path, "a")
        if log then
            log.writeLine(line)
            log.close()
        end
    end
end


function run()
    initLogging("Run.log")
    Logger.setLevel("info")
    local runId = os.date("!%Y-%m-%dT%H:%MZ")
    Logger.info("[run] id=" .. runId, "goal=" .. table.concat(args, " "))
    Logger.runId = runId
    local s = Server(Logger)
    if #args > 0 then
        local command = table.concat(args, " ")
        Logger.info("executing CLI command:", command)
        s.cli:setEnabled(false)
        s.cli:clearBuffer()
        s.cli:handleCommand(command)
        s.cli:setEnabled(true)
        s.cli:drawPrompt()
    end
    s:run()
end

run()

--local ok, res = xpcall(run, debug.traceback)
--textutils.pagedPrint(res)
