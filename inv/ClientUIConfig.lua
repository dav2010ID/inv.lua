local Config = {}

Config.moveKeys = {w=-4, s=4, a=-1, d=1}

Config.keyActions = {
    request = "q",
    store = "e",
    storeAll = "E",
    refresh = "r",
    refreshScan = "R",
    plus = "=",
    plusMod = "+",
    minus = "-",
    minusMod = "_"
}

Config.labels = {
    refresh = "Refresh",
    scan = "ScanNet",
    store = "Store",
    storeAll = " All ",
    request = "Request"
}

return Config
