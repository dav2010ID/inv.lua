local Class = require 'inv.core.Class'

-- Stores known crafting machines and their availability.
local MachineRegistry = Class:subclass()

function MachineRegistry:init(server)
    self.server = server
    self.logger = server.logger
    -- table<string, table<string, Machine>>: indexed by machine type and device name.
    self.machines = {}
end

-- Adds a crafting machine to the network, updating network state as necessary.
function MachineRegistry:addMachine(device)
    if not device.type then
        self.logger.warn("[craft] skipped machine with unknown type", device.name)
        return
    end
    local machineTable = self.machines[device.type]
    if not machineTable then
        machineTable = {}
        self.machines[device.type] = machineTable
    end
    machineTable[device.name] = device
end

-- Removes a crafting machine from the network, updating network state as necessary.
function MachineRegistry:removeMachine(device)
    local machineTable = device.type and self.machines[device.type] or nil
    if machineTable then
        machineTable[device.name] = nil
    end
end

function MachineRegistry:getMachines(machineType)
    return self.machines[machineType]
end

function MachineRegistry:countMachines(machineType)
    local machinesOfType = self.machines[machineType]
    if not machinesOfType then
        return 0
    end
    local n = 0
    for _, _ in pairs(machinesOfType) do
        n = n + 1
    end
    return n
end

function MachineRegistry:countAvailableMachines(machineType)
    local machinesOfType = self.machines[machineType]
    if not machinesOfType then
        return 0
    end
    local n = 0
    for _, machine in pairs(machinesOfType) do
        if not machine:isBusy() then
            n = n + 1
        end
    end
    return n
end

-- Finds a non-busy crafting machine of the given type,
-- returning nil if none is found.
function MachineRegistry:findMachine(machineType)
    local machinesOfType = self.machines[machineType]
    if machinesOfType then
        for _, machine in pairs(machinesOfType) do
            if not machine:isBusy() then
                return machine
            end
        end
    end
    return nil
end

return MachineRegistry



