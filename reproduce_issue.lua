package.loaded["cc.expect"] = function(...) end

-- Mock required modules that might cause side effects or are complex
package.loaded["inv.infrastructure.Log"] = {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Mock peripheral
_G.peripheral = {
    wrap = function(name)
        return {
            getItemDetail = function() return nil end,
            list = function() return {} end,
            pushItems = function() return 0 end,
            pullItems = function() return 0 end
        }
    end,
    getName = function() return "test_machine" end
}

local Recipe = require 'inv.domain.Recipe'
local GtceuMachine = require 'inv.infrastructure.device.GtceuMachine'


-- Mock Server
local Server = {
    machineRegistry = {
        addMachine = function() end,
        removeMachine = function() end
    }
}

-- Mock Backend
local Backend = {
    getItemDetail = function(self, slot)
        if slot == 1 then
            return { name = "gtceu:plate_mold" }
        end
        return nil
    end,
    craft = function() end
}

local function runTest()
    print("Starting tests...")

    -- Test 1: Recipe Creation (should succeed now)
    local r = Recipe({
        machine = "compressor",
        input = { ["1"] = { name = "minecraft:cobblestone", count = 1 } },
        output = { ["1"] = { name = "minecraft:stone", count = 1 } },
        modifiers = { "mold:gtceu:plate_mold" },
        id = "test_recipe"
    })
    print("Test 1 Passed: Recipe created with mold modifier")

    -- Test 2: Machine satisfaction
    local machine = GtceuMachine(Server, "test_machine", "compressor", { modifierSlots = { 1 } }, Backend)

    -- Mock task with recipe
    local task = { recipe = r }

    if machine:canAcceptTasks(task) then
        print("Test 2 Passed: Machine accepted task with valid mold")
    else
        error("Test 2 Failed: Machine failed to accept task with valid mold")
    end

    -- Test 3: Machine without mold
    local BackendNoMold = {
        getItemDetail = function() return nil end,
        craft = function() end
    }
    local machineNoMold = GtceuMachine(Server, "test_machine_2", "compressor", { modifierSlots = { 1 } }, BackendNoMold)
    if machineNoMold:canAcceptTasks(task) then
        error("Test 3 Failed: Machine unexpectedly accepted task without mold")
    else
        print("Test 3 Passed: Machine correctly rejected task without mold")
    end
end

local success, err = pcall(runTest)

if not success then
    print("TEST FAILED: " .. tostring(err))
    os.exit(1)
else
    print("ALL TESTS PASSED")
end
