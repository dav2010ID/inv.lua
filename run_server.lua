local Server = require 'inv.runtime.Server'
local Logger = require 'inv.infrastructure.Log'

local args = {...}

local function initLogging(path, maxSize)
    maxSize = maxSize or (32 * 1024) -- 32 KB default
    local oldPrint = print
    local warned = false

    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        local line = table.concat(parts, " ")

        oldPrint(line)

        local free = fs.getFreeSpace("/")
        if free < 4096 then
            if fs.exists(path) then
                fs.delete(path)
            end
            if not warned then
                oldPrint("[warn] low disk space; file logging disabled")
                warned = true
            end
            return
        end

        local log = fs.open(path, "a")
        if log then
            log.writeLine(line)
            log.close()
        end
    end
end


function run()
    initLogging("Run.log", 32 * 1024)
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
