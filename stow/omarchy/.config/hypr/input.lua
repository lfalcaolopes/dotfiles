-- kb_layout e kb_variant ficam fora daqui: o input.lua padrao do Omarchy os le
-- de /etc/vconsole.conf, que o modulo 05-locale converge para us/intl.
hl.config({
  input = {
    kb_options = "compose:ralt,shift:both_capslock_cancel",
    repeat_delay = 600,
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = false,
      drag_3fg = 1,
    },
  },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

-- Three-finger focus gestures conflict with drag_3fg, so they stay disabled.
