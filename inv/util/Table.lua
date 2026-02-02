local Table = {}

function Table.copyShallow(tab)
    local o = {}
    for k,v in pairs(tab) do
        o[k] = v
    end
    return o
end

-- Warning: Will explode with recursive table.
function Table.copyDeep(tab)
    local o = {}
    for k,v in pairs(tab) do
        if type(v) == "table" then
            o[k] = Table.copyDeep(v)
        else
            o[k] = v
        end
    end
    return o
end

function Table.removeItem(t, item)
    for i=1,#t do
        if t[i] == item then
            table.remove(t, i)
            return
        end
    end
end

function Table.integerKeys(t)
    local x = {}
    for k, v in pairs(t) do
        x[tonumber(k)] = v
    end
    return x
end

return Table
