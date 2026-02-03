local to = peripheral.wrap("top")
local from = peripheral.wrap("back")

-- переместить все предметы из слота 2 в слот 1
print(to.pullItems(peripheral.getName(from), 1, 1, 2))

