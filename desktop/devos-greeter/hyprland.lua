-- DevOS login screen compositor (SRS DESK-010, D-03).
-- greetd starts this minimal Hyprland as the "greeter" user; it only shows the DevOS
-- login screen (Quickshell, layer-shell), so login and desktop share one GPU path.
--   Hyprland --config /usr/share/devos/greeter/hyprland.lua

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})

hl.config({
    general = {
        border_size = 0,
        gaps_in = 0,
        gaps_out = 0
    },
    decoration = {
        rounding = 0,
        shadow = { enabled = false },
        blur = { enabled = false }
    },
    animations = {
        enabled = true
    },
    input = {
        kb_layout = "us",
        numlock_by_default = true,
        follow_mouse = 1
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "rgb(070a11)",
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true
    },
    cursor = {
        -- Hardware cursor planes are unreliable on virtual GPUs.
        no_hardware_cursors = 1,
        -- Hide the pointer until it moves (it starts over the login card).
        inactive_timeout = 3
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true
    }
})

-- Fade the login screen in; it is a layer surface.
hl.curve("devosDecel", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1} } })
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "devosDecel", style = "fade" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "devosDecel" })

hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/devos/devos-greeter-ui")
end)
