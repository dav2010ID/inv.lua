local Log = {}

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

function Log.cli(...)
    emit(nil, ...)
end

function Log.info(...)
    emit("[info] ", ...)
end

function Log.warn(...)
    emit("[warn] ", ...)
end

function Log.error(...)
    emit("[error] ", ...)
end

return Log
