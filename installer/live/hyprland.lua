-- DevOS live ISO session (SRS §7.1): a minimal Hyprland that shows the graphical installer.
--   Hyprland --config /usr/share/devos-installer/hyprland.lua   (see devos-live-session)
-- The installer is a layer surface on the bottom layer; a terminal (Super+Enter, or the
-- installer's Terminal button) opens above it as a normal window.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})

hl.config({
    general = {
        border_size = 2,
        gaps_in = 6,
        gaps_out = 16,
        col = {
            active_border = { colors = { "rgba(2dd4bfee)", "rgba(8b5cf6ee)" }, angle = 45 },
            inactive_border = "rgba(3f484baa)"
        }
    },
    decoration = {
        rounding = 17,
        shadow = { enabled = true, range = 24, render_power = 3, color = "rgba(00000066)" },
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
        no_hardware_cursors = 1
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true
    }
})

hl.curve("devosDecel", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1} } })
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "devosDecel", style = "fade" })
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "devosDecel", style = "popin 90%" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "devosDecel" })

local mainMod = "SUPER"
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())

hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/devos-installer/devos-installer-ui")
end)
