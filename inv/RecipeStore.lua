local Object = require 'object.Object'
local Recipe = require 'inv.Recipe'

-- Stores recipes and helps resolve outputs to crafting recipes.
local RecipeStore = Object:subclass()

function RecipeStore:init(server)
    self.server = server
    self.logger = server.logger
    -- table<string, Recipe>: Recipes known to this network, indexed by item ID.
    self.recipes = {}
end

-- Loads recipes from the given data.
-- Data should consist of an array of tables, with each table
-- in the format required by the Recipe class.
function RecipeStore:loadRecipes(data)
    for i, spec in ipairs(data) do
        local recipe = Recipe(spec)
        for slot, item in pairs(recipe.output) do
            assert(item.name) -- output should not be generic
            if not self.recipes[item.name] then
                self.recipes[item.name] = recipe
                self.logger.info("[craft] added recipe", item.name)
            end
            local info = self.server.inventoryService:getItem(item.name)
            if not info then
                info = self.server.inventoryService:addItem(item.name)
            end
            if not info.detailed and item.tags then
                for tag, v in pairs(item.tags) do
                    info.tags[tag] = v
                end
                self.server.inventoryService:updateTags(info.name)
            end
        end
    end
end

-- Finds a recipe to produce the given item,
-- returning nil if none is found.
function RecipeStore:findRecipe(item)
    local results = self.server.inventoryService:resolveCriteria(item)
    for name, v in pairs(results) do
        local recipe = self.recipes[name]
        if recipe then
            self.logger.debug("[craft] recipe found", name)
            return recipe
        end
    end
    return nil
end

return RecipeStore
