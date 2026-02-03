while true do
  local ev = { os.pullEventRaw() }
  print(textutils.serialize(ev))
end
