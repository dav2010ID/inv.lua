local expect = require "cc.expect"

local function instanceToString(self)
    local class = rawget(self, "class")
    local className = class and rawget(class, "__name") or "Object"
    local name = rawget(self, "name") or rawget(self, "id")
    if name ~= nil then
        return string.format("%s(%s)", className, tostring(name))
    end
    return className
end

local function instanceEquals(a, b)
    return rawequal(a, b)
end

-- Creates an instance of a class, and then calls the class's init() method
-- with the provided arguments.
local function new(class, ...)
    local instance = setmetatable({}, class.instanceMeta)
    local ok, err = pcall(instance.init, instance, ...)
    if not ok then
        error(err, 2) -- propagate error up to caller
    end
    return instance
end

-- Converts a table into a class.
local function makeClass(class, superClass)
    class.class = class
    class.superClass = superClass
    if not class.__name then
        class.__name = (superClass and superClass.__name) or "Object"
    end
    class.instanceMeta = {
        __index = class,
        __tostring = instanceToString,
        __eq = instanceEquals,
        __name = class.__name
    }
    return setmetatable(class, {__index=superClass, __call=new})
end

-- Implements basic inheritance features.
local Object = {}

makeClass(Object)

-- Object constructor.
--
-- To create an instance of an Object, call Object(args), which will instantiate
-- the class and then call the Object's constructor to set up the instance.
-- The process works the same way for subclasses: just replace Object with the
-- name of the class you are instantiating.
--
-- Internally, the constructor is named Object:init(...). Override this init
-- method to specify initialization behavior for an Object subclass. An object's
-- init() method may call its super class's init() if desired
-- (use ClassName.superClass.init(self,...))
function Object:init(...) end

-- Creates a subclass of an existing class.
function Object:subclass()
    return makeClass({}, self)
end

-- Returns true if the Object is an instance of the provided class or a subclass.
function Object:instanceof(class)
    expect(1, class, "table")
    local c = self.class
    while c ~= nil do
        if c == class then
            return true
        end
        c = c.superClass
    end
    return false
end

return Object
