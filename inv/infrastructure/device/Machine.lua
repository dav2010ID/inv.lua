local Class = require 'inv.core.Class'
local Device = require 'inv.infrastructure.device.Device'
local Table = require 'inv.infrastructure.util.Table'

-- Represents a crafting machine.
local Machine = Device:subclass()

local CraftSession = Class:subclass()

function CraftSession:init(server, machine, recipe, dest, destSlot, craftCount)
    self.server = server
    self.machine = machine
    self.recipe = recipe
    self.dest = dest
    self.destSlot = destSlot
    self.craftCount = craftCount or 1
    self.remaining = {}
    for slot, item in pairs(self.recipe.output) do
        self.remaining[slot] = item.count * self.craftCount
    end
    self.state = "input"
end

function CraftSession:prepareInputs()
    self.state = "input"
    self.machine.state = "input"
    local pushed = {}
    for virtSlot, crit in pairs(self.recipe.input) do
        local realSlot = self.machine:mapSlot(virtSlot)
        local needed = crit:copy()
        needed.count = crit.count * self.craftCount
        if self.machine and type(self.machine.getItemLimit) == "function" then
            local limit = self.machine:getItemLimit(realSlot)
            if limit and limit > 0 then
                local current = 0
                local detail = self.machine:getItemDetail(realSlot)
                if detail then
                    if not crit:matches(detail) then
                        return false, "insufficient_input"
                    end
                    current = detail.count or 0
                end
                local available = limit - current
                if available < needed.count then
                    return false, "insufficient_input"
                end
            end
        end
        local n = self.server.inventoryMutator:push(self.machine, needed, needed.count, realSlot)
        pushed[virtSlot] = n
        if n < needed.count then
            self:rollbackInputs(pushed)
            return false, "insufficient_input"
        end
    end
    return true
end

function CraftSession:rollbackInputs(pushed)
    for virtSlot, n in pairs(pushed) do
        if n and n > 0 then
            local realSlot = self.machine:mapSlot(virtSlot)
            local detail = self.machine:getItemDetail(realSlot)
            if detail then
                detail.count = math.min(detail.count or n, n)
                self.server.inventoryMutator:pull(self.machine, detail, detail.count, realSlot)
            end
        end
    end
end

function CraftSession:startCraft()
    self.state = "crafting"
    self.machine.state = "crafting"
    self.machine:startCraft(self.craftCount)
    return true
end

function CraftSession:validateOutput(virtSlot, item)
    return self.recipe.output[virtSlot]:matches(item)
end

function CraftSession:consumeOutput(virtSlot, item, realSlot)
    local n = self.server.inventoryMutator:pull(self.machine, item, item.count, realSlot)
    self.remaining[virtSlot] = self.remaining[virtSlot] - n
    return n
end

function CraftSession:forwardOutput(virtSlot, count)
    if not self.dest or count <= 0 then
        return
    end
    local outItem = self.recipe.output[virtSlot]:copy()
    outItem.count = count
    self.server.inventoryMutator:push(self.dest, outItem, outItem.count, self.destSlot)
end

function CraftSession:drainOutput()
    if self.machine and type(self.machine.isOutputReady) == "function" then
        if not self.machine:isOutputReady(self) then
            return true
        end
    end
    self.state = "output"
    self.machine.state = "output"
    for virtSlot, rem in pairs(self.remaining) do
        if rem > 0 then
            local realSlot = self.machine:mapSlot(virtSlot)
            local item = self.machine:getItemDetail(realSlot)
            if item then
                if not self:validateOutput(virtSlot, item) then
                    return false, "unexpected_output"
                end
                local n = self:consumeOutput(virtSlot, item, realSlot)
                self:forwardOutput(virtSlot, n)
            end
        end
    end
    if self:isDone() then
        self:close()
    end
    return true
end

function CraftSession:isDone()
    for _, rem in pairs(self.remaining) do
        if rem > 0 then
            return false
        end
    end
    return true
end

function CraftSession:close()
    self.state = "idle"
    self.machine:clearSession(self)
end

function Machine:init(server, name, deviceType, config, backend)
    Machine.superClass.init(self, server, name, deviceType, config)
    self.config = self.config or {}

    assert(backend, "backend required")
    self.backend = backend
    self.backendName = self.backend.name or (self.config.backend or "peripheral")
    assert(self.backend.getItemDetail, "backend missing getItemDetail")
    assert(self.backend.craft, "backend missing craft")

    if self.config.slots then
        self.slots = Table.integerKeys(self.config.slots)
        self.useIdentitySlots = false
    elseif self.backend.defaultSlots then
        self.slots = Table.copyDeep(self.backend.defaultSlots)
        self.useIdentitySlots = false
    else
        self.slots = {}
        self.useIdentitySlots = true
    end

    self.craftOutputSlot = self.config.craftOutputSlot or 10

    self.modifiers = {}
    if type(self.config.modifiers) == "table" then
        for _, value in ipairs(self.config.modifiers) do
            if type(value) == "string" and value ~= "" then
                self.modifiers[value] = true
            end
        end
    elseif type(self.config.modifiers) == "string" and self.config.modifiers ~= "" then
        self.modifiers[self.config.modifiers] = true
    end

    if self.config.location then
        self.location = self.config.location
    elseif self.backend.resolveLocation then
        self.location = self.backend.resolveLocation(self)
    else
        self.location = self.name
    end

    self.state = "idle"
    self.activeSession = nil

    self.server.machineRegistry:addMachine(self)
end

function Machine:destroy()
    self.server.machineRegistry:removeMachine(self)
end

-- Maps a virtual slot number from a Recipe to an actual slot in this Machine's inventory.
function Machine:mapSlot(virtSlot)
    assert(type(virtSlot) == "number", "virtSlot must be a number")
    if self.useIdentitySlots then
        return virtSlot
    end
    local realSlot = self.slots[virtSlot]
    assert(realSlot, "missing slot mapping for " .. tostring(virtSlot))
    return realSlot
end

function Machine:getCraftOutputSlot()
    return self:mapSlot(self.craftOutputSlot or 10)
end

function Machine:getItemDetail(slot)
    return self.backend.getItemDetail(self, slot)
end

function Machine:startCraft(count)
    self.backend.craft(self, count)
end

function Machine:createSession(recipe, dest, destSlot, craftCount)
    if self.activeSession then
        return nil, "busy"
    end
    local session = CraftSession(self.server, self, recipe, dest, destSlot, craftCount)
    self.activeSession = session
    self.state = "input"
    return session
end

function Machine:clearSession(session)
    if self.activeSession == session then
        self.activeSession = nil
        self.state = "idle"
    end
end

-- Returns true if this machine is currently crafting.
function Machine:isBusy()
    return self.activeSession ~= nil
end

function Machine:hasModifiers(required)
    if not required then
        return true
    end
    for key, _ in pairs(required) do
        if not self.modifiers or not self.modifiers[key] then
            return false
        end
    end
    return true
end

function Machine:canAcceptTasks(task)
    local required = task and task.recipe and task.recipe.modifiers or nil
    return self:hasModifiers(required)
end

function Machine:isFinished()
    if not self.activeSession then
        return true
    end
    return self.activeSession:isDone()
end

return Machine
