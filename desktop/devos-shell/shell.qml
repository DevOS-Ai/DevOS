//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// DevOS desktop shell additions, one Quickshell process (started by Hyprland):
//   - DevOS Agent panel (SRS AI-001)   keybind: hl.dsp.global("devos:aiToggle")
//   - first-login Welcome (SRS §7.2)   reopen:  qs -p /usr/share/devos/shell ipc call devos welcome
ShellRoot {
    AgentClient { id: client }

    AiPanel {
        id: panel
        client: client
    }

    StatusPill {
        client: client
        panel: panel
    }

    Welcome {
        id: welcome
        client: client
        onOpenAiPanel: panel.open = true
    }

    // Keybind target: hl.dsp.global("devos:aiToggle") — no process spawn per keypress.
    // Super+Ctrl+A: open the agent with the focused window as context.
    GlobalShortcut {
        appid: "devos"
        name: "aiAskWindow"
        description: "Ask DevOS Agent about the focused window"
        onPressed: {
            const w = ToplevelManager.activeToplevel;
            const title = w ? (w.title || "") : "";
            const cls = w ? (w.appId || "") : "";
            panel.prefill(title ? "About the focused window \u201c" + title + "\u201d" + (cls ? " (" + cls + ")" : "") + ": " : "");
            panel.open = true;
        }
    }

    GlobalShortcut {
        appid: "devos"
        name: "aiToggle"
        description: "Toggle the DevOS AI panel"
        onPressed: panel.open = !panel.open
    }

    IpcHandler {
        target: "devos-ai"
        function toggle(): void { panel.open = !panel.open; }
        function open(): void { panel.open = true; }
        function close(): void { panel.open = false; }
        // Open the panel and send a task right away, e.g. from a script or another app:
        //   qs -p /usr/share/devos/shell ipc call devos-ai ask "summarize ~/notes/today.md"
        function ask(text: string): void { panel.open = true; client.send(text); }
        // Open a view of the panel: chat | history | jobs | skills | memory | settings
        //   qs -p /usr/share/devos/shell ipc call devos-ai view settings
        function view(name: string): void { panel.open = true; panel.go(name); }
        // For the bar indicator: off | idle | thinking | running | waiting | error
        function status(): string { return client.status; }
    }

    IpcHandler {
        target: "devos"
        function welcome(): void { welcome.show(); }
    }
}
