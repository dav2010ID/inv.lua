local Log = {}

Log.levels = {debug=10, info=20, warn=30, error=40}
Log.level = Log.levels.info

local lastByKey = {}

local function now()
    if os.epoch then
        return os.epoch("utc") / 1000
    end
    return os.clock()
end

local function joinArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        parts[i] = tostring(value)
    end
    return table.concat(parts, " ")
end

local function emit(prefix, ...)
    local message = joinArgs(...)
    if prefix then
        print(prefix .. message)
    else
        print(message)
    end
end

local function shouldLog(level)
    return Log.level <= level
end

function Log.setLevel(name)
    local level = Log.levels[name]
    if level then
        Log.level = level
    end
end

function Log.throttle(key, intervalSeconds, level, prefix, ...)
    if not shouldLog(level) then
        return
    end
    local t = now()
    local last = lastByKey[key]
    if not last or (t - last) >= intervalSeconds then
        lastByKey[key] = t
        emit(prefix, ...)
    end
end

function Log.cli(...)
    emit(nil, ...)
end

function Log.debug(...)
    if shouldLog(Log.levels.debug) then
        emit("[debug] ", ...)
    end
end

function Log.info(...)
    if shouldLog(Log.levels.info) then
        emit("[info] ", ...)
    end
end

function Log.warn(...)
    if shouldLog(Log.levels.warn) then
        emit("[warn] ", ...)
    end
end

function Log.error(...)
    if shouldLog(Log.levels.error) then
        emit("[error] ", ...)
    end
end

return Log
