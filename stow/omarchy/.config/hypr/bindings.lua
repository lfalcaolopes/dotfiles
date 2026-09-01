hl.config({
  binds = {
    workspace_back_and_forth = true,
  },
})

-- SUPER + W is bound by Omarchy to its default close dispatcher.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", "hypr-close-window")

-- Swap Omarchy's window and monitor cycling shortcuts.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
hl.unbind("CTRL + ALT + TAB")
hl.unbind("CTRL + ALT + SHIFT + TAB")

o.bind("ALT + TAB", "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }))
o.bind("ALT + SHIFT + TAB", "Focus on previous monitor", hl.dsp.focus({ monitor = "-1" }))
o.bind("CTRL + ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("CTRL + ALT + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
o.bind("CTRL + ALT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
o.bind("CTRL + ALT + SHIFT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
