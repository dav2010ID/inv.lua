local Class = require 'inv.core.Class'
local Item = require 'inv.domain.Item'

-- Describes a crafting recipe.
local Recipe = Class:subclass()

local function normalizeSlot(slot)
    local num = tonumber(slot)
    assert(num ~= nil, "recipe slot must be a number")
    return num
end

local function validateItemSpec(spec, label, slot)
    assert(type(spec) == "table", label .. " must be an item spec")
    if spec.count ~= nil then
        assert(spec.count > 0, label .. " item count must be > 0 at slot " .. tostring(slot))
    end
end

local function buildKey(machine, input, output)
    local function slotList(map)
        local slots = {}
        for slot, _ in pairs(map) do
            table.insert(slots, slot)
        end
        table.sort(slots)
        local parts = {}
        for _, slot in ipairs(slots) do
            local item = map[slot]
            local key = item.identityKey and item:identityKey() or (item.name or "unknown")
            table.insert(parts, tostring(slot) .. ":" .. key .. ":" .. tostring(item.count or 0))
        end
        return table.concat(parts, ",")
    end
    return "machine=" .. tostring(machine) .. ";in=" .. slotList(input) .. ";out=" .. slotList(output)
end

function Recipe:init(spec)
    assert(spec and type(spec) == "table", "recipe spec must be a table")
    assert(spec.machine, "recipe machine is required")
    assert(type(spec.input) == "table", "recipe input must be a table")
    assert(type(spec.output) == "table", "recipe output must be a table")
    -- string: The type of machine that can craft this recipe.
    self.machine = spec.machine
    -- SlotMap<int, Item>: The items used as input to this recipe.
    self.input = {}
    -- SlotMap<int, Item>: The items returned as output from this recipe.
    self.output = {}

    -- Note: slot normalization should ideally happen in the recipe loader.
    for slot, itemSpec in pairs(spec.input) do
        local normSlot = normalizeSlot(slot)
        validateItemSpec(itemSpec, "recipe input", normSlot)
        self.input[normSlot] = Item(itemSpec)
    end
    for slot, itemSpec in pairs(spec.output) do
        local normSlot = normalizeSlot(slot)
        validateItemSpec(itemSpec, "recipe output", normSlot)
        self.output[normSlot] = Item(itemSpec)
    end

    assert(next(self.output) ~= nil, "recipe output must not be empty")
    assert(next(self.input) ~= nil or spec.allowEmptyInput, "recipe input must not be empty")

    self.id = spec.id or buildKey(self.machine, self.input, self.output)
end

-- Returns scaled copies of the input items for the given craft count.
function Recipe:scaledInputs(craftCount)
    local count = craftCount or 1
    local inputs = {}
    for _, item in pairs(self.input) do
        local copy = item:copy()
        copy.count = copy.count * count
        table.insert(inputs, copy)
    end
    return inputs
end

-- Returns the total produced count for the given criteria.
function Recipe:countProduced(criteria)
    local total = 0
    for _, item in pairs(self.output) do
        if criteria:matches(item) then
            total = total + item.count
        end
    end
    return total
end

function Recipe:getProducedCount(criteria)
    return self:countProduced(criteria)
end

function Recipe:matchesOutput(criteria)
    return self:countProduced(criteria) > 0
end

return Recipe



