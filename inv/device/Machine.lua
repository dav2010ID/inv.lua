local Device = require 'inv.device.Device'
local Common = require 'inv.Common'
local Log = require 'inv.Log'

-- Represents a crafting machine.
local Machine = Device:subclass()

local defaultWorkbenchSlots = {
    [1]=1,  [2]=2,  [3]=3,
    [4]=5,  [5]=6,  [6]=7,
    [7]=9,  [8]=10, [9]=11,
    [10]=16
}

local backends = {}

backends.peripheral = {
    name = "peripheral",
    getItemDetail = function(machine, slot)
        return machine.interface.getItemDetail(slot)
    end,
    craft = function(machine, count) end,
    locationResolver = function(machine)
        return machine.name
    end
}

backends.turtle = {
    name = "turtle",
    defaultSlots = defaultWorkbenchSlots,
    getItemDetail = function(machine, slot)
        return turtle.getItemDetail(slot, true)
    end,
    craft = function(machine, count)
        local outSlot = machine:getCraftOutputSlot()
        if outSlot then
            turtle.select(outSlot)
        end
        local times = count or 1
        for i = 1, times do
            local ok = turtle.craft()
            if not ok then
                Log.warn("[machine] craft failed", machine.name)
                break
            end
        end
    end,
    locationResolver = function(machine)
        return Common.getNameLocal()
    end
}

local function resolveBackend(name)
    if name and backends[name] then
        return backends[name]
    end
    return backends.peripheral
end

function Machine:init(server, name, deviceType, config)
    Machine.superClass.init(self, server, name, deviceType, config)
    self.config = self.config or {}
    -- Recipe: The recipe currently being crafted by this Machine.
    self.recipe = nil
    -- table<int, int>: Optional mapping between virtual slots used in recipes
    -- and real slots in the Machine's inventory.
    self.slots = nil
    -- Device: Where crafted items should be sent. Optional.
    self.dest = nil
    -- int: Slot within self.dest where crafted items should be sent. Optional.
    self.destSlot = nil
    -- table<int, Item>: Remaining items that this Machine is currently crafting.
    self.remaining = {}

    self.backendName = self.config.backend or "peripheral"
    self.backend = resolveBackend(self.backendName)

    if self.config.slots then
        self.slots = Common.integerKeys(self.config.slots)
    elseif self.backend.defaultSlots then
        self.slots = Common.deepCopy(self.backend.defaultSlots)
    end

    self.craftOutputSlot = self.config.craftOutputSlot or 10

    if self.config.location then
        self.location = self.config.location
    elseif self.backend.locationResolver then
        self.location = self.backend.locationResolver(self)
    end

    self.server.craftRegistry:addMachine(self)
end

function Machine:destroy()
    self.server.craftRegistry:removeMachine(self)
end

-- Maps a virtual slot number from a Recipe
-- to an actual slot in this Machine's inventory.
function Machine:mapSlot(virtSlot)
    if self.slots and self.slots[virtSlot] then
        return self.slots[virtSlot]
    end
    return virtSlot
end

function Machine:getCraftOutputSlot()
    return self:mapSlot(self.craftOutputSlot or 10)
end

function Machine:getItemDetail(slot)
    if self.backend and self.backend.getItemDetail then
        return self.backend.getItemDetail(self, slot)
    end
    return Machine.superClass.getItemDetail(self, slot)
end

function Machine:performCraft(count)
    if self.backend and self.backend.craft then
        self.backend.craft(self, count)
    end
end

function Machine:rollbackInputs(pushed)
    for virtSlot, n in pairs(pushed) do
        if n and n > 0 then
            local realSlot = self:mapSlot(virtSlot)
            local detail = self:getItemDetail(realSlot)
            if detail then
                detail.count = math.min(detail.count or n, n)
                local moved = self.server.inventoryIO:pullItemsFrom(detail, self, realSlot)
                if moved < detail.count then
                Log.warn("[machine] rollback incomplete", self.name, detail.name or "unknown")
                end
            end
        end
    end
end

-- Starts a crafting operation.
-- dest and destSlot are optional.
function Machine:craft(recipe, dest, destSlot, craftCount)
    if self:busy() then error("machine " .. self.name .. " busy") end
    local count = craftCount or 1
    self.recipe = recipe
    self.dest = dest
    self.destSlot = destSlot
    self.remaining = {}
    for slot, item in pairs(self.recipe.output) do
        self.remaining[slot] = item.count * count
    end
    local pushed = {}
    for virtSlot, crit in pairs(self.recipe.input) do
        local realSlot = self:mapSlot(virtSlot)
        local needed = crit:copy()
        needed.count = crit.count * count
        local n = self.server.inventoryIO:pushItemsTo(needed, self, realSlot)
        pushed[virtSlot] = n
        if n < needed.count then
            Log.warn("[machine] insufficient input for", self.name)
            self:rollbackInputs(pushed)
            self.recipe = nil
            self.dest = nil
            self.destSlot = nil
            self.remaining = {}
            return false
        end
    end
    self:performCraft(count)
    return true
end

-- Returns true if this machine is currently crafting.
function Machine:busy()
    return self.recipe ~= nil
end

-- Empties an output slot of the machine and counts any crafted items.
function Machine:handleOutputSlot(item, virtSlot, realSlot)
    if item then
        local n = self.server.inventoryIO:pullItemsFrom(item, self, realSlot)
        if self.recipe.output[virtSlot]:matches(item) then
            self.remaining[virtSlot] = self.remaining[virtSlot] - n
            if self.dest then
                local outItem = self.recipe.output[virtSlot]:copy()
                outItem.count = n
                self.server.inventoryIO:pushItemsTo(outItem, self.dest, self.destSlot)
            end
        else
            Log.warn("[machine] unexpected output", item.name, "in", self.name)
        end
    end
end

-- Empties all output slots of this machine, counting the crafted items
-- and updating the machine state as necessary.
function Machine:pullOutput()
    for virtSlot, rem in pairs(self.remaining) do
        local realSlot = self:mapSlot(virtSlot)
        local item = self:getItemDetail(realSlot)
        self:handleOutputSlot(item, virtSlot, realSlot)
    end
    for virtSlot, rem in pairs(self.remaining) do
        if rem > 0 then
            return
        end
    end
    self.recipe = nil
end

return Machine
