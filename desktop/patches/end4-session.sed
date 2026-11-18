# DESK-021: log out through UWSM. end-4 kills Hyprland directly, which skips UWSM's
# ordered shutdown of the session units (the Hyprland wiki warns against it).
# Falls back to end-4's behaviour when the session is not managed by UWSM.
s|^\(\s*\)Quickshell.execDetached(\["pkill", "-i", "Hyprland"\]);$|\1Quickshell.execDetached(["bash", "-c", "uwsm stop \|\| pkill -i Hyprland"]);|
