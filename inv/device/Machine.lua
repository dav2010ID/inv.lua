local Device = require 'inv.device.Device'
local Common = require 'inv.Common'

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
    craft = function(machine) end,
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
    craft = function(machine)
        local outSlot = machine:getCraftOutputSlot()
        if outSlot then
            turtle.select(outSlot)
        end
        turtle.craft()
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

function Machine:performCraft()
    if self.backend and self.backend.craft then
        self.backend.craft(self)
    end
end

-- Starts a crafting operation.
-- dest and destSlot are optional.
function Machine:craft(recipe, dest, destSlot)
    if self:busy() then error("machine " .. self.name .. " busy") end
    self.recipe = recipe
    self.dest = dest
    self.destSlot = destSlot
    self.remaining = {}
    for slot, item in pairs(self.recipe.output) do
        self.remaining[slot] = item.count
    end
    for virtSlot, crit in pairs(self.recipe.input) do
        local n = self.server.inventoryIO:pushItemsTo(crit, self, self:mapSlot(virtSlot))
        assert(n == crit.count)
    end
    self:performCraft()
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
            print("[machine] unexpected output " .. item.name .. " in " .. self.name)
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
