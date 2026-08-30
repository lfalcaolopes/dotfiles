hl.monitor({
  output = "eDP-1",
  mode = "1920x1080@60",
  position = "0x0",
  scale = 1,
})

for _, workspace in ipairs({ 6, 7, 8, 9, 10 }) do
  hl.workspace_rule({ workspace = tostring(workspace), monitor = "eDP-1" })
end
