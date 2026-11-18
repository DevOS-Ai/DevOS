# DESK-021: compatibility fix for end-4's general.lua.
# Current Hyprland caps decoration.shadow.render_power at 4; end-4's pinned commit
# sets 10, which Hyprland rejects with a config error banner on every login.
# 4 is the closest allowed value (sharpest shadow falloff).
s|^\(\s*render_power = \)10,$|\14,|
