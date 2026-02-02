local Net = require 'inv.util.Net'
local Table = require 'inv.util.Table'

local Common = {}

Common.PROTOCOL = Net.PROTOCOL
Common.SIDES = Net.SIDES

Common.getModemSide = Net.getModemSide
Common.getModem = Net.getModem
Common.getNameLocal = Net.getNameLocal

Common.shallowCopy = Table.copyShallow
Common.deepCopy = Table.copyDeep
Common.removeItem = Table.removeItem
Common.integerKeys = Table.integerKeys

return Common
