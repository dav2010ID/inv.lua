local test = peripheral.wrap("top")
local f = fs.open("slots.txt", "w")

for i = 1, 4 do
  local d = test.getItemDetail(i)

  if d then
    f.writeLine(i .. textutils.serialize(d))
  else
    f.writeLine(i .. " empty")
  end
    sleep(0)
end
f.close()