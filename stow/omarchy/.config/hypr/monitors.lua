local primary = "desc:Acer Technologies QG241Y P"

hl.env("GDK_SCALE", "1")

hl.monitor({
  output = primary,
  mode = "1920x1080@165",
  position = "auto",
  scale = 1,
})

for _, workspace in ipairs({ 1, 2, 3, 4, 5 }) do
  hl.workspace_rule({ workspace = tostring(workspace), monitor = primary })
end

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
