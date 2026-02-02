local Class = require 'inv.core.Class'
local Item = require 'inv.domain.Item'

-- Describes a crafting recipe.
local Recipe = Class:subclass()

function Recipe:init(spec)
    -- string: The type of machine that can craft this recipe.
    self.machine = spec.machine
    -- table<int, Item>: The items used as input to this recipe,
    -- indexed by inventory slot.
    self.input = {}
    -- table<int, Item>: The items returned as output from this recipe,
    -- indexed by inventory slot.
    self.output = {}

    -- JSON requires that dictionary keys be strings, so the inventory slots
    -- in the recipe must be converted to int when the recipe is loaded.
    for slot, itemSpec in pairs(spec.input) do
        self.input[tonumber(slot)] = Item(itemSpec)
    end
    for slot, itemSpec in pairs(spec.output) do
        self.output[tonumber(slot)] = Item(itemSpec)
    end
end

return Recipe



