# Architecture

## Layers

- core: Fundamental runtime utilities. No dependencies on other layers.
- domain: Pure model and state. Depends only on core.
- craft, services: Business logic and orchestration. Depend on domain and core.
- infrastructure: ComputerCraft peripherals, IO, and network. Depends on core and domain.
- runtime: Composition and main loop. Depends on all layers.

## Module layout

- inv/core
- inv/domain
- inv/craft
- inv/services
- inv/infrastructure
- inv/runtime

## Class (OOP base)

`inv/core/Class.lua` provides core runtime support for class-based OOP in Lua. It is not a domain concept and must not encode business rules.

## Dependency checks

Layering is enforced by convention and can be verified by grepping `require` statements.

## Example: custom storage class

1) Create a new device class in `inv/infrastructure/device/`.

```lua
-- inv/infrastructure/device/SmartStorage.lua
local Storage = require 'inv.infrastructure.device.Storage'

local SmartStorage = Storage:subclass()

function SmartStorage:init(server, name, deviceType, config)
    SmartStorage.superClass.init(self, server, name, deviceType, config)
    self.onlyTags = config.onlyTags or nil
end

function SmartStorage:itemAllowed(item)
    if not SmartStorage.superClass.itemAllowed(self, item) then
        return false
    end
    if not self.onlyTags then
        return true
    end
    for tag, _ in pairs(self.onlyTags) do
        if item.tags and item.tags[tag] then
            return true
        end
    end
    return false
end

return SmartStorage
```

2) Wire it into `inv/infrastructure/DeviceCatalog.lua`.

```lua
local SmartStorage = require 'inv.infrastructure.device.SmartStorage'

-- inside createDevice(...)
elseif purpose == "storage" then
    if config.storageClass == "smart" then
        local storage = SmartStorage(self.server, name, deviceType, config)
        self.logger.debug("[device] storage attached", name, "type", deviceType or "inventory")
        return storage
    end
    local storage = Storage(self.server, name, deviceType, config)
    self.logger.debug("[device] storage attached", name, "type", deviceType or "inventory")
    return storage
end
```

3) Configure it in `config/devices/*.json`.

```json
{
  "type": "minecraft:barrel",
  "purpose": "storage",
  "storageClass": "smart",
  "onlyTags": {"forge:ingots/iron": true}
}
```

4) Reload: run `devices` in CLI (and `scan` if needed).

## OOP extension guide: storage and machines

### Storage: class design

- Base class: `inv/infrastructure/device/Storage.lua`
- Required: call `Storage.superClass.init(self, ...)` in `init` so the device is registered in `StorageRegistry`.
- Override points:
  - `itemAllowed(item)` to control which items may be stored.
  - `list()` (from `Device`) if you want to hide or virtualize contents.
  - `destroy()` if you need extra teardown; always call `super` to keep registries consistent.

Suggested config pattern:
- `storageClass` discriminator in JSON (e.g., `"storageClass": "smart"`).
- Custom fields for rules (e.g., `onlyTags`, `denyTags`, `maxStacks`).

### Storage: example of policy-based override

```lua
-- inv/infrastructure/device/QuotaStorage.lua
local Storage = require 'inv.infrastructure.device.Storage'

local QuotaStorage = Storage:subclass()

function QuotaStorage:init(server, name, deviceType, config)
    QuotaStorage.superClass.init(self, server, name, deviceType, config)
    self.maxStacks = config.maxStacks or nil
end

function QuotaStorage:itemAllowed(item)
    if not QuotaStorage.superClass.itemAllowed(self, item) then
        return false
    end
    if not self.maxStacks then
        return true
    end
    local count = 0
    for _, entry in pairs(self:list()) do
        count = count + 1
        if count >= self.maxStacks then
            return false
        end
    end
    return true
end

return QuotaStorage
```

### Machine: class design

- Base class: `inv/infrastructure/device/Machine.lua`
- Required: call `Machine.superClass.init(self, ...)` in `init` so the device is registered in `MachineRegistry`.
- Override points:
  - `performCraft(count)` for custom craft behavior.
  - `mapSlot(virtSlot)` if the machine has a non-standard slot layout.
  - `getItemDetail(slot)` if the backend needs a special read path.
  - `pullOutput()` if output handling is custom.

### Machine backends

`Machine` supports backends to abstract peripheral behavior. The backend object implements:
- `getItemDetail(machine, slot)`
- `craft(machine, count)`
- `resolveLocation(machine)`
- `defaultSlots` (optional)

Add backends via `inv/infrastructure/machine/BackendRegistry.lua` and select them with `config.backend`.

### DeviceCatalog wiring

For new storage or machine types, add a `require` and a small branch in `DeviceCatalog:createDevice`:

```lua
local QuotaStorage = require 'inv.infrastructure.device.QuotaStorage'

-- inside createDevice(...)
elseif purpose == "storage" then
    if config.storageClass == "quota" then
        return QuotaStorage(self.server, name, deviceType, config)
    end
    return Storage(self.server, name, deviceType, config)
end
```

### Config examples

```json
{
  "type": "minecraft:barrel",
  "purpose": "storage",
  "storageClass": "quota",
  "maxStacks": 10
}
```
