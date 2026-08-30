hl.config({
  binds = {
    workspace_back_and_forth = true,
  },
})

-- SUPER + W is bound by Omarchy to its default close dispatcher.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", "hypr-close-window")
