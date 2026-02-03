local BackendRegistry = {}

local backends = {}
local defaultName = "peripheral"

local function register(name, backend)
    assert(name, "backend name required")
    assert(backend and type(backend) == "table", "backend table required")
    backends[name] = backend
end

local function resolve(name)
    local key = name or defaultName
    local backend = backends[key]
    assert(backend, "backend not registered: " .. tostring(key))
    assert(type(backend.getItemDetail) == "function", "backend missing getItemDetail")
    assert(type(backend.craft) == "function", "backend missing craft")
    return backend
end

local function default()
    return defaultName
end

register("peripheral", {
    name = "peripheral",
    getItemDetail = function(machine, slot)
        return machine.interface.getItemDetail(slot)
    end,
    craft = function(machine, count) end,
    resolveLocation = function(machine)
        return machine.name
    end,
    defaultSlots = nil
})
register("gtceu", {
    name = "gtceu",
    getItemDetail = function(machine, slot)
        return machine.interface.getItemDetail(slot)
    end,
    craft = function(machine, count) end,
    resolveLocation = function(machine)
        return machine.name
    end,
    defaultSlots = nil
})


BackendRegistry.register = register
BackendRegistry.resolve = resolve
BackendRegistry.default = default

return BackendRegistry
