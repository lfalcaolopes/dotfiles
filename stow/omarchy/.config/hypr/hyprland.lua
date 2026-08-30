dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

require("default.hypr.omarchy")

require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("hypr.host")

require("default.hypr.toggles")

o.window("^([bB]rave-browser)$", { workspace = "1 silent" })
o.window("^(code)$",             { workspace = "2 silent" })
o.window("^([dD][bB]eaver)$",    { workspace = "3 silent" })
o.window("^([Pp]ostman)$",       { workspace = "4 silent" })
o.window("^([sS]team)$",         { workspace = "5 silent" })
o.window("^brave-web\\.whatsapp\\.com__", { workspace = "6 silent" })

o.window("^([sS]team)$",   { tile = true })
o.window("^([Pp]ostman)$", { tile = true })
