-- Os dois monitores do desktop, ambos com posição absoluta.
--
-- Pinar os dois é obrigatório, não preferência. O stow/omarchy/.config/hypr/
-- monitors.lua declara o primário com position = "auto", e o hyprland.lua
-- carrega hypr.host depois de hypr.monitors. Fixar só o secundário em 1920x0
-- faz o "auto" do primário resolver depois, achar 1920x0 ocupado e cair em
-- 3840x0, deixando 0-1920 vazio. Com os dois fixos aqui não sobra ordem para
-- dar errado.
--
-- Casar por descrição, e não por DP-1 e HDMI-A-1, sobrevive a trocar o cabo de
-- porta. Os dois são Acer, então o modelo é o que desambigua; o serial não
-- precisa entrar.
local primary = "desc:Acer Technologies QG241Y P"
local secondary = "desc:Acer Technologies GN246HL"

hl.monitor({
  output = primary,
  mode = "1920x1080@165",
  position = "0x0",
  scale = 1,
})

hl.monitor({
  output = secondary,
  mode = "1920x1080@60",
  position = "1920x0",
  scale = 1,
})

-- As workspaces 1-5 já ficam no primário por monitors.lua, que casa pela mesma
-- descrição e segue valendo.
for _, workspace in ipairs({ 6, 7, 8, 9, 10 }) do
  hl.workspace_rule({ workspace = tostring(workspace), monitor = secondary })
end
