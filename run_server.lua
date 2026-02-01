local Server = require 'inv.Server'

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
    local s = Server()
    s:mainLoop()
end

run()

--local ok, res = xpcall(run, debug.traceback)
--textutils.pagedPrint(res)
