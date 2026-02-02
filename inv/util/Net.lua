local Net = {}

Net.PROTOCOL = "inv"
Net.SIDES = {"top","bottom","left","right","front","back"}

Net.modem = nil
Net.modemSide = nil

function Net.getModemSide()
    if not Net.modemSide then
        for i, side in ipairs(Net.SIDES) do
            if peripheral.getType(side) == "modem" and peripheral.wrap(side).getNameLocal then
                Net.modemSide = side
                break
            end
        end
    end
    return Net.modemSide
end

function Net.getModem()
    if not Net.modem then
        Net.modem = peripheral.wrap(Net.getModemSide())
    end
    return Net.modem
end

function Net.getNameLocal()
    return Net.getModem().getNameLocal()
end

return Net
