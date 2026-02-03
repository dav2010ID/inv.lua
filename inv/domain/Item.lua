local Class = require 'inv.core.Class'

-- Represents various types of items, including optional details such as name,
-- display name, and Ore Dictionary tags.
-- Used for both tracking counts of stored items and setting criteria for
-- operations such as crafting and item retrieval.
-- Role note: as criteria, count is a minimum requirement; as stack, count is
-- the actual quantity (detailed is typically true).
local Item = Class:subclass()

local function normalizeTags(tags)
    local result = {}
    if not tags then
        return result
    end
    if tags[1] then
        for _, tag in ipairs(tags) do
            result[tag] = true
        end
    else
        for tag, _ in pairs(tags) do
            result[tag] = true
        end
    end
    return result
end

function Item:init(spec)
    spec = spec or {}
    -- string: The name (item ID) of the item, e.g. "minecraft:cobblestone".
    -- Optional.
    self.name = spec.name

    -- bool: Whether this Item contains complete information as reported by
    -- inventory.getItemDetail()
    self.detailed = spec.detailed or false
    -- string: The translated display name of the item, e.g. "Cobblestone".
    -- Optional.
    self.displayName = spec.displayName
    -- int: Maximum allowed count of the item within a stack (usually 64).
    -- Optional.
    self.maxCount = spec.maxCount

    -- table: Ore Dictionary tags attached to this item.
    -- Always present, but may be empty.
    self.tags = normalizeTags(spec.tags)

    -- int: The number of items in this item stack (default 1).
    self.count = 1
    if spec.count ~= nil then
        self.count = spec.count
    end
end

-- Returns true if the other item satisfies the criteria specified by this Item.
-- Note: self is treated as criteria; item is treated as fact.
-- If a name is present on this item, the two must match.
-- Otherwise, at least one matching Ore Dictionary tag must be present on both.
function Item:matches(item)
    if self.name then
        return self.name == item.name
    end
    if item.tags then
        for tag, v in pairs(self.tags) do
            if item.tags[tag] then
                return true
            end
        end
    end
    return false
end

-- Returns a stable identity key for criteria matching (ignores count).
function Item:identityKey()
    if self.name then
        return "name:" .. self.name
    end
    if self.tags then
        local keys = {}
        for tag, _ in pairs(self.tags) do
            table.insert(keys, tag)
        end
        table.sort(keys)
        return "tags:" .. table.concat(keys, ",")
    end
    return "unknown"
end

-- Returns true if the given item both matches the criteria as specified by Item:match,
-- and has a count greater than or equal to this item's count.
-- If count is provided, it overrides item.count for comparison.
function Item:matchesCount(item, count)
    if not self:matches(item) then
        return false
    end
    if count == nil then
        count = item.count
    end
    return count >= self.count
end

-- Returns a copy of this Item.
function Item:copy()
    return Item({
        name = self.name,
        detailed = self.detailed,
        displayName = self.displayName,
        maxCount = self.maxCount,
        tags = normalizeTags(self.tags),
        count = self.count
    })
end

-- Static method. Given an array of Items, combines any item stacks that match
-- each other into single stacks.
function Item.stack(items)
    local stacked = {}
    for slot, item in pairs(items) do
        local i = 1
        local didStack = false
        for i, item2 in ipairs(stacked) do
            local key = item.name or item:identityKey()
            local otherKey = item2.name or item2:identityKey()
            if key == otherKey then
                item2.count = item2.count + item.count
                didStack = true
                break
            end
        end
        if not didStack then
            table.insert(stacked, item:copy())
        end
    end
    return stacked
end

-- Adds details to the Item as returned by inventory.getItemDetail()
function Item:setDetails(details)
    self.displayName = details.displayName
    self.maxCount = details.maxCount
    self.tags = normalizeTags(details.tags)
    self.detailed = true
end

-- Returns a display name for the Item, falling back to Item.name if not present.
function Item:getName()
    return self.displayName or self.name
end

-- Returns the Item's information as a plain table.
function Item:serialize()
    local t = {}
    t.name = self.name
    t.count = self.count
    t.detailed = self.detailed
    t.displayName = self.displayName
    t.maxCount = self.maxCount
    t.tags = normalizeTags(self.tags)
    return t
end

return Item



