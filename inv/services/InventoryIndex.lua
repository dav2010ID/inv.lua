local Class = require 'inv.core.Class'
local Item = require 'inv.domain.Item'

-- Indexes items and tags for the inventory system.
local InventoryIndex = Class:subclass()

function InventoryIndex:init()
    -- table<string, Item>: The items stored in this network.
    -- Indexed by name of the item.
    self.items = {}
    -- table<string, table<string, Item>>: All items associated with each Ore
    -- Dictionary tag previously seen on this network.
    self.tags = {}
    -- bool: Whether the current state of the stored items has been updated.
    -- If true, then changes should be processed by the server loop.
    self.updated = false
    -- table<string, bool>: Items that have changed since the last update.
    self.updatedItems = {}
end

-- Given an item name, registers a new item in the database.
function InventoryIndex:registerItem(name)
    local info = Item{name=name, count=0}
    self.items[name] = info
    return info
end

function InventoryIndex:addItem(name)
    return self:registerItem(name)
end

-- Given a detail specification for an item, adds or updates the associated
-- item in the database if necessary.
function InventoryIndex:updateDB(detail)
    if not detail or not detail.name then
        return
    end
    local info = self.items[detail.name]

    if not info then
        info = self:registerItem(detail.name)
    end

    if not info.detailed then
        info:setDetails(detail)
        self:updateTags(info.name)
    end
end

-- Files the item under its given tags.
function InventoryIndex:updateTags(name)
    local info = self.items[name]
    for tag, v in pairs(info.tags) do
        local entries = self.tags[tag]
        if not entries then
            entries = {}
            self.tags[tag] = entries
        end
        entries[name] = info
    end
end

-- Given a list of items to find, returns a list of requested items that are
-- not stored in the network.
-- todo: improve this
function InventoryIndex:tryMatchAll(searchItems)
    local s = Item.stack(searchItems)
    for name, item in pairs(self.items) do
        local n = item.count

        local i = 1
        while i <= #s do
            local searchItem = s[i]
            -- TODO: is this check necessary now that Item.stack is used?
            if searchItem:matchesCount(item,n) then
                n = n - searchItem.count
                table.remove(s, i)
            else
                i = i + 1
            end
        end
    end
    return s
end

-- Returns a list of all known item types matching the given specification.
function InventoryIndex:resolveCriteria(criteria)
    local result = {}
    if criteria.name then
        result[criteria.name] = true
    elseif criteria.tags then
        for tag, v in pairs(criteria.tags) do
            local entries = self.tags[tag]
            if entries then
                for name, item in pairs(entries) do
                    result[name] = true
                end
            end
        end
    end
    return result
end

function InventoryIndex:markUpdated(name)
    self.updated = true
    self.updatedItems[name] = true
end

-- Returns a list of items changed since the last update,
-- with all items serialized to a plain table format.
function InventoryIndex:getUpdatedItems()
    if self.updated then
        local u = {}
        for name, v in pairs(self.updatedItems) do
            u[name] = self.items[name]:serialize()
        end
        self.updated = false
        self.updatedItems = {}
        return u
    end
    return nil
end

return InventoryIndex



