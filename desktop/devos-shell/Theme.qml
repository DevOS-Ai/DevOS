pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// DevOS design tokens: one design system with the end-4 desktop (Material You).
//
// Colors are the Material 3 roles end-4 uses, read live from the scheme matugen generates
// from the wallpaper (~/.local/state/quickshell/user/generated/colors.json), so the DevOS
// panel, Welcome and dialogs change with the wallpaper exactly like the bar and sidebars.
// Without that file (the login screen, or before the first wallpaper) the DevOS scheme
// below applies: the same teal and violet as the GRUB theme and boot splash.
// Shape, type and motion follow end-4's Appearance (rounding scale, Google Sans Flex,
// Material Symbols Rounded, expressive curves).
Singleton {
    id: theme

    // ---------------------------------------------------------------- M3 scheme
    // DevOS fallback scheme (dark, source color #2DD4BF).
    property color m3background: "#0e1416"
    property color m3onBackground: "#dee3e5"
    property color m3surface: "#0e1416"
    property color m3surfaceContainerLowest: "#090f11"
    property color m3surfaceContainerLow: "#161d1f"
    property color m3surfaceContainer: "#1a2123"
    property color m3surfaceContainerHigh: "#252b2d"
    property color m3surfaceContainerHighest: "#2f3638"
    property color m3onSurface: "#dee3e5"
    property color m3surfaceVariant: "#3f484b"
    property color m3onSurfaceVariant: "#bfc8cb"
    property color m3outline: "#899295"
    property color m3outlineVariant: "#3f484b"
    property color m3primary: "#53dbc9"
    property color m3onPrimary: "#003731"
    property color m3primaryContainer: "#005048"
    property color m3onPrimaryContainer: "#74f8e5"
    property color m3secondary: "#b1ccc6"
    property color m3onSecondary: "#1c3531"
    property color m3secondaryContainer: "#334b47"
    property color m3onSecondaryContainer: "#cce8e2"
    property color m3tertiary: "#c9bfff"
    property color m3onTertiary: "#30236c"
    property color m3tertiaryContainer: "#473b84"
    property color m3onTertiaryContainer: "#e6deff"
    property color m3error: "#ffb4ab"
    property color m3onError: "#690005"
    property color m3errorContainer: "#93000a"
    property color m3onErrorContainer: "#ffdad6"
    property color m3inverseSurface: "#dee3e5"
    property color m3inverseOnSurface: "#2b3133"
    property color m3scrim: "#000000"
    property bool dark: true
    property bool fromWallpaper: false

    // The scheme matugen writes for end-4 (snake_case keys: "surface_container_low", …).
    FileView {
        id: scheme
        // DEVOS_THEME_FILE: a fixed scheme (the login screen uses the default wallpaper's).
        path: Quickshell.env("DEVOS_THEME_FILE")
              || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                 + "/quickshell/user/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let json;
            try { json = JSON.parse(text()); } catch (e) { return; }
            for (const key in json) {
                const prop = "m3" + key.replace(/_([a-z])/g, (m, c) => c.toUpperCase());
                if (prop in theme && typeof json[key] === "string") theme[prop] = json[key];
            }
            theme.dark = theme.m3background.hslLightness < 0.5;
            theme.fromWallpaper = true;
        }
    }

    // ------------------------------------------------- semantic tokens (used by DevOS UI)
    // Layers, as in end-4: 0 = window, 1 = card, 2 = raised, 3 = selected / input.
    readonly property color layer0: m3surfaceContainerLow
    readonly property color layer1: m3surfaceContainer
    readonly property color layer2: m3surfaceContainerHigh
    readonly property color layer3: m3surfaceContainerHighest
    readonly property color layerText: m3onSurface
    function hover(base, on) { return Qt.tint(base, Qt.rgba(on.r, on.g, on.b, 0.08)); }
    function pressed(base, on) { return Qt.tint(base, Qt.rgba(on.r, on.g, on.b, 0.14)); }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    // Names the DevOS components already use, mapped onto the M3 roles.
    readonly property color bg: alpha(layer0, 0.97)
    readonly property color surface: layer1
    readonly property color surfaceHigh: layer2
    readonly property color border: alpha(m3outlineVariant, 0.9)
    readonly property color text: m3onSurface
    readonly property color muted: m3onSurfaceVariant
    readonly property color faint: m3outline
    readonly property color teal: m3primary            // accent
    readonly property color accentText: m3onPrimary
    readonly property color violet: m3tertiary         // second accent
    readonly property color danger: m3error
    readonly property color warning: dark ? "#f5c26b" : "#7a5900"
    readonly property color success: dark ? "#8fd8a8" : "#1f6c3d"

    // ---------------------------------------------------------------- shape
    readonly property int radiusSmall: 12
    readonly property int radius: 17
    readonly property int radiusLarge: 23
    readonly property int radiusFull: 9999
    readonly property int gap: 12

    // ---------------------------------------------------------------- type
    readonly property string display: "Google Sans Flex"
    readonly property string body: "Google Sans Flex"
    readonly property string mono: "JetBrains Mono"
    readonly property string icons: "Material Symbols Rounded"

    // ---------------------------------------------------------------- motion (end-4 curves)
    readonly property list<real> expressiveFast: [0.42, 1.67, 0.21, 0.90, 1, 1]       // 350 ms
    readonly property list<real> expressiveDefault: [0.38, 1.21, 0.22, 1.00, 1, 1]    // 500 ms
    readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
    readonly property int durationFast: 200
    readonly property int durationNormal: 350
}
