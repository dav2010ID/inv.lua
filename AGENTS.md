## Architecture overview
- Layering (enforced by convention):  
  - `core`: runtime utilities (no dependencies)  
  - `domain`: pure model/state (depends on `core`)  
  - `craft`, `services`: business logic (depend on `domain` + `core`)  
  - `infrastructure`: peripherals/IO/network (depends on `core` + `domain`)  
  - `runtime`: composition + main loop (depends on all layers)
- Module layout mirrors layers under `inv/`:
  - `inv/core`, `inv/domain`, `inv/craft`, `inv/services`, `inv/infrastructure`, `inv/runtime`
- OOP base: `inv/core/Class.lua` (runtime support only; no business rules).
- Device wiring:
  - `inv/infrastructure/DeviceCatalog.lua` creates devices based on config.  
  - Storage/Machine base classes are in `inv/infrastructure/device/`.
  - Machine backends are registered via `inv/infrastructure/machine/BackendRegistry.lua`.

## Project structure (top-level)
- `inv/`: source modules (layered architecture).
- `config/`: runtime configuration (devices and recipes).
- `tools/`: helper scripts/utilities (if any).
- `run_server.lua`: entrypoint for the server turtle.
- `README.md`, `ARCHITECTURE.md`: user docs and architecture notes.

## Key modules by responsibility
- `inv/runtime/Server.lua`: wiring of services and runtime loop.
- `inv/runtime/RuntimeLoop.lua`: main tick loop and event handling.
- `inv/runtime/CliController.lua`: CLI command parsing and UI.
- `inv/infrastructure/DeviceCatalog.lua`: device discovery and instantiation.
- `inv/infrastructure/InventoryIO.lua`: push/pull operations and index updates.
- `inv/infrastructure/MachineRegistry.lua`: known machines by type.
- `inv/services/MachineScheduler.lua`: assigns machines to tasks.
- `inv/services/TaskScheduler.lua`: task lifecycle and summary metrics.
- `inv/craft/CraftPlanner.lua`: recipe planning and craft graphs.
- `inv/craft/TaskFactory.lua`: task creation and priority calculation.
- `inv/domain/Recipe.lua`: recipe data model and scaling helpers.
- `inv/domain/CraftTask.lua`: craft task state model.

## Data flow overview
- Device discovery: `DeviceCatalog` scans peripherals and creates `Storage` or `Machine`.
- Inventory view: `InventoryIO` scans devices and updates `InventoryIndex`.
- Craft request: CLI -> `CraftExecutor` -> `CraftPlanner` -> `TaskFactory` -> `TaskScheduler`.
- Machine execution: `TaskScheduler` creates `CraftSession` on a `Machine`, pushes inputs, starts craft, drains outputs.
- Scheduling: `MachineScheduler` picks free machines and enforces queue order.

## Configuration details
- Devices: `config/devices/*.json`
- Recipes: `config/recipes/*.json`
- Config loader: `inv/infrastructure/Config.lua`
- Run from repo root so relative config paths resolve.

## Runtime expectations
- CC:Tweaked "generic peripherals" must be enabled.
- Server runs headless on the crafting turtle.
## Configuration & runtime notes

Пайплайн craft (от команды до завершения)
Ниже — по шагам, с привязкой к ключевым модулям/файлам.

Ввод команды и первичная проверка
Команда парсится в CliController.lua.
craft <item> <count> делает:
берёт текущее количество из inventoryQuery
если уже хватает — завершает
иначе считает missing и вызывает планировщик
Файл: CliController.lua
Планирование по рецепту
CraftPlanner:plan ищет рецепт в RecipeStore и считает количество крафтов по выходу рецепта (ceil).
Файлы: CraftPlanner.lua, RecipeStore.lua, Recipe.lua
Постановка задач
TaskQueue:queuePlan:
создаёт summary через TaskScheduler:createSummary
разбивает на батчи по числу доступных машин (MachineScheduler:countAvailableMachines)
для каждого батча создаёт CraftTask
регистрирует задачи в TaskScheduler
Файл: TaskFactory.lua
Построение графа зависимостей (inputs)
TaskGraphBuilder:link вызывает CraftGraph.link:
проверяет наличие входов через inventoryQuery:tryMatchAll
если чего-то нет: ищет рецепт для зависимого предмета и энкьюит подзадачу
если рецепта нет или цикл — создаёт wait‑задачу
Файл: CraftGraph.lua
Запуск и цикл исполнения
RuntimeLoop на каждом тике дергает TaskScheduler:tick.
Файл: RuntimeLoop.lua
Основная логика выполнения CraftTask
TaskScheduler:
если сессия уже есть, пытается слить output и завершить
если сессии нет:
проверяет наличие входов
при отсутствии ставит blocked и (если надо) догенерит зависимости
при наличии входов пробует получить машину
Файл: TaskScheduler.lua
Выбор машины
MachineScheduler:schedule выдаёт свободную машину нужного типа или ставит задачу в очередь.
Причины ожидания: machine_capacity, machine_priority, machine_unavailable.
Файл: MachineScheduler.lua
Сессия крафта и I/O
Machine:createSession создаёт CraftSession.
CraftSession:prepareInputs:
мапит слоты
пушит нужные предметы из склада в машину через InventoryMutator.push
CraftSession:startCraft вызывает backend craft (реальный запуск машины).
Файлы: Machine.lua, InventoryService.lua, InventoryIO.lua
Снятие результата
CraftSession:drainOutput:
ждёт готовность (если backend умеет isOutputReady)
проверяет, что output соответствует рецепту
тянет output обратно в склад через InventoryMutator.pull
опционально пересылает в dest (в CLI dest обычно nil)
Файл: Machine.lua
Завершение и метрики
Когда output полностью вычищен:
сессия закрывается, машина освобождается
задача помечается done
summary обновляется; при завершении всех батчей печатается сводка
Файл: TaskScheduler.lua
Ключевые нюансы

CLI‑команда craft не вызывает CraftExecutor:pushOrCraftItemsTo; она сразу планирует крафт по недостающему количеству. Файл: CraftExecutor.lua
Граф зависимостей строится заранее, но при блокировке по входам может достраиваться ещё раз (если needsDependencies не сброшен).