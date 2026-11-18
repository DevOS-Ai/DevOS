# DESK-021: end-4's first run on DevOS. The DevOS background is the default wallpaper
# (end-4 derives the shell, terminal and app colors from it), and the DevOS Welcome
# replaces end-4's welcome app (still available with Super+Shift+Alt+/).
s|^\(\s*property string defaultWallpaperPath: \).*$|\1"/usr/share/backgrounds/devos/devos.jpg"|
s|^\(\s*\)Quickshell.execDetached(\["bash", "-c", `qs -p '\${root.welcomeQmlPath}'`\])$|\1// DevOS: the DevOS Welcome is shown instead (devos-shell).|
