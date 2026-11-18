-- DevOS (added by devos-desktop). Your own keybinds can go below.
-- Super+A opens DevOS Agent (patched into end-4's keybinds.lua); Super+Ctrl+A opens it
-- with the focused window as context ("what is this error?", "fix this", …).
hl.bind("SUPER + CTRL + A", hl.dsp.global("devos:aiAskWindow"), { description = "DevOS Agent: ask about the focused window" })
