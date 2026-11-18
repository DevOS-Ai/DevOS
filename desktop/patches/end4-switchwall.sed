# DESK-021: keep the matugen-rendered material_colors.scss when end-4's Python color
# step cannot run (its materialyoucolor module is not in the official repositories).
# The Python output still replaces it when that step succeeds.
s|^\(\s*\)> "\$STATE_DIR"/user/generated/material_colors.scss$|\1> "$STATE_DIR"/user/generated/material_colors.scss.py \&\& mv "$STATE_DIR"/user/generated/material_colors.scss.py "$STATE_DIR"/user/generated/material_colors.scss|
