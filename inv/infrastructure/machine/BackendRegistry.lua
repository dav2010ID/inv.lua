local BackendRegistry = {}

local backends = {}

local function register(name, backend)
    assert(name, "backend name required")
    backends[name] = backend
end

local function resolve(name)
    local key = name or "peripheral"
    local backend = backends[key]
    assert(backend, "backend not registered: " .. tostring(key))
    assert(type(backend.getItemDetail) == "function", "backend missing getItemDetail")
    assert(type(backend.craft) == "function", "backend missing craft")
    assert(type(backend.resolveLocation) == "function", "backend missing resolveLocation")
    return backend
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


BackendRegistry.register = register
BackendRegistry.resolve = resolve

return BackendRegistry
