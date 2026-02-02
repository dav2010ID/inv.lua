local Object = require 'object.Object'
local Config = require 'inv.infrastructure.Config'
local MachineScheduler = require 'inv.services.MachineScheduler'
local CraftExecutor = require 'inv.craft.CraftExecutor'
local DeviceCatalog = require 'inv.infrastructure.DeviceCatalog'
local InventoryService = require 'inv.services.InventoryService'
local RecipeStore = require 'inv.services.RecipeStore'
local MachineRegistry = require 'inv.infrastructure.MachineRegistry'
local StorageRegistry = require 'inv.infrastructure.StorageRegistry'
local TaskScheduler = require 'inv.services.TaskScheduler'
local CliController = require 'inv.runtime.CliController'
local EventDispatcher = require 'inv.runtime.EventDispatcher'
local RuntimeLoop = require 'inv.runtime.RuntimeLoop'

local Server = Object:subclass()

function Server:init(logger)
    self.logger = logger or require 'inv.infrastructure.Log'
    local deviceConfig, recipeConfig = self:loadConfig()
    self:setup(deviceConfig, recipeConfig)
    self.cli = CliController(self)
    self.eventDispatcher = EventDispatcher(self, self.cli)
    self.runtime = RuntimeLoop(self, self.eventDispatcher, self.cli)
end

function Server:loadConfig()
    local configDir = "config/"
    local deviceConfig = Config.loadDirectory(configDir .. "devices")
    local recipeConfig = Config.loadDirectory(configDir .. "recipes")
    return deviceConfig, recipeConfig
end

function Server:setup(deviceConfig, recipeConfig)
    self.inventoryService = InventoryService(self)
    self.storageRegistry = StorageRegistry(self)
    self.deviceCatalog = DeviceCatalog(self, deviceConfig)
    self.recipeStore = RecipeStore(self)
    self.machineRegistry = MachineRegistry(self)
    self.machineScheduler = MachineScheduler(self, self.machineRegistry)
    self.craftExecutor = CraftExecutor(self)
    self.taskScheduler = TaskScheduler(self)
    if self.logger and self.logger.runId then
        self.taskScheduler.currentRunId = self.logger.runId
    end

    self.recipeStore:loadRecipes(recipeConfig)
    self.deviceCatalog:scanDevices()
end

function Server:run()
    self.runtime:run()
end

return Server
