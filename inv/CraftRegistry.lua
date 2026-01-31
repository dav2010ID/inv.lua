local Object = require 'object.Object'
local Recipe = require 'inv.Recipe'

-- Stores recipes and known crafting machines.
local CraftRegistry = Object:subclass()

function CraftRegistry:init(server)
    self.server = server
    -- table<string, Recipe>: Recipes known to this network, indexed by item ID.
    self.recipes = {}
    -- table<string, table<string, Machine>>: Crafting machines connected to
    -- this network, indexed by machine type and device name.
    self.machines = {}
end

-- Adds a crafting machine to the network, updating network state as necessary.
function CraftRegistry:addMachine(device)
    local machineTable = self.machines[device.type]
    if not machineTable then
        machineTable = {}
        self.machines[device.type] = machineTable
    end
    machineTable[device.name] = device
end

-- Removes a crafting machine from the network, updating network state as necessary.
function CraftRegistry:removeMachine(device)
    self.machines[device.type][device.name] = nil
end

-- Loads recipes from the given data.
-- Data should consist of an array of tables, with each table
-- in the format required by the Recipe class.
function CraftRegistry:loadRecipes(data)
    for i, spec in ipairs(data) do
        local recipe = Recipe(spec)
        for slot, item in pairs(recipe.output) do
            assert(item.name) -- output should not be generic
            if not self.recipes[item.name] then
                self.recipes[item.name] = recipe
                print("[craft] added recipe",item.name)
            end
            local info = self.server.inventoryIndex.items[item.name]
            if not info then
                info = self.server.inventoryIndex:addItem(item.name)
            end
            if not info.detailed and item.tags then
                for tag, v in pairs(item.tags) do
                    info.tags[tag] = v
                end
                self.server.inventoryIndex:updateTags(info.name)
            end
        end
    end
end

-- Finds a recipe to produce the given item,
-- returning nil if none is found.
function CraftRegistry:findRecipe(item)
    local results = self.server.inventoryIndex:resolveCriteria(item)
    for name, v in pairs(results) do
        local recipe = self.recipes[name]
        if recipe then
            print("[craft] recipe found",name)
            return recipe
        end
    end
    return nil
end

-- Finds a non-busy crafting machine of the given type,
-- returning nil if none is found.
function CraftRegistry:findMachine(machineType)
    local machinesOfType = self.machines[machineType]
    if machinesOfType then
        for name, machine in pairs(machinesOfType) do
            if not machine:busy() then
                return machine
            end
            print("[craft]",name,"busy")
        end
    end
    print("[craft] no",machineType,"found")
    return nil
end

return CraftRegistry
