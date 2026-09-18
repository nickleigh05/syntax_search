import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "qml"

PanelWindow {
    id: win

    readonly property string backend: Quickshell.shellDir + "/docset_index.py"
    property bool panelVisible: true

    color: "transparent"
    visible: panelVisible
    focusable: panelVisible
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "syntax-search"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    implicitWidth: Theme.windowWidth
    implicitHeight: Theme.windowHeight

    function showPanel() {
        panelVisible = true;
        panel.grabFocus();
    }

    function hidePanel() {
        panelVisible = false;
    }

    IpcHandler {
        target: "panel"

        function toggle(): void {
            if (win.panelVisible) win.hidePanel(); else win.showPanel();
        }
        function show(): void { win.showPanel(); }
        function hide(): void { win.hidePanel(); }
        function switchDocset(): void {
            win.showPanel();
            panel.openDocsetMenu();
        }
        function quit(): void { Qt.quit(); }
    }

    Component.onCompleted: {
        if (Quickshell.env("SYNTAX_SEARCH_MODE") === "switch") panel.openDocsetMenu();
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.glass
        border.width: 1
        border.color: Theme.glassBorder
        clip: true

        SearchPanel {
            id: panel
            anchors.fill: parent
            backend: win.backend
            onRequestHide: win.hidePanel()
        }
    }
}
