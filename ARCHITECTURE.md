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

## Object (OOP base)

`inv/core/Object.lua` provides core runtime support for class-based OOP in Lua. It is not a domain concept and must not encode business rules.

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
