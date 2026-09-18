import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

Item {
    id: root

    required property string backend
    property string docsetName: ""

    property string symbolName: ""
    property string symbolType: ""
    property string symbolPath: ""
    property string signature: ""
    property string bodyHtml: ""
    property string pageTitle: ""
    property string url: ""
    property bool truncated: false
    property string status: "idle"
    property string message: ""
    property var cache: ({})
    property string requestKey: ""

    signal focusInput()

    readonly property bool paneFocused: body.activeFocus

    function reset() {
        symbolName = "";
        symbolType = "";
        symbolPath = "";
        signature = "";
        bodyHtml = "";
        pageTitle = "";
        url = "";
        status = "idle";
        cache = ({});
    }

    function show(name, type, path) {
        symbolName = name;
        symbolType = type;
        symbolPath = path;
        const key = docsetName + "\u0000" + path;
        requestKey = key;
        const hit = cache[key];
        if (hit) {
            apply(hit);
            return;
        }
        status = "loading";
        signature = name;
        bodyHtml = "";
        fetchDebounce.restart();
    }

    function apply(data) {
        signature = data.signature || symbolName;
        bodyHtml = styleHtml(data.html || "");
        pageTitle = data.pageTitle || "";
        url = data.url || "";
        truncated = Boolean(data.truncated);
        status = bodyHtml.trim().length > 0 ? "ready" : "empty";
        flick.contentY = 0;
    }

    function styleHtml(h) {
        return h
            .replace(/<pre style="/g, '<pre style="background-color:' + Theme.codeBg + '; padding:6px; ')
            .replace(/<code style="/g, '<code style="color:' + Theme.codeText + '; ')
            .replace(/<h1>/g, '<h1 style="font-size:22px">')
            .replace(/<h2>/g, '<h2 style="font-size:19px">')
            .replace(/<h3>/g, '<h3 style="font-size:17px">');
    }

    function navigate(link) {
        if (link.startsWith("doc:")) {
            const target = link.substring(4);
            const hashAt = target.indexOf("#");
            const label = hashAt >= 0 ? target.substring(hashAt + 1) : target;
            show(label, "", target);
            return;
        }
        Quickshell.execDetached(["xdg-open", link]);
    }

    function openInBrowser() {
        if (url.length > 0) Quickshell.execDetached(["xdg-open", url]);
    }

    function scrollBy(pages) {
        const step = flick.height * 0.85 * pages;
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + step));
    }

    function focusPane() {
        if (status === "ready") body.forceActiveFocus();
    }

    Timer {
        id: fetchDebounce
        interval: 110
        onTriggered: {
            describer.running = false;
            describer.running = true;
        }
    }

    Process {
        id: describer
        command: ["python3", root.backend, "--describe", root.docsetName, root.symbolPath, "--name=" + root.symbolName]
        stdout: StdioCollector {
            onStreamFinished: {
                let data;
                try { data = JSON.parse(this.text); } catch (e) {
                    root.status = "error";
                    root.message = "Could not parse description";
                    return;
                }
                if (data.status !== "ok") {
                    root.status = "error";
                    root.message = data.message || "Unknown error";
                    return;
                }
                const key = root.docsetName + "\u0000" + root.symbolPath;
                const c = root.cache;
                c[key] = data;
                root.cache = c;
                if (key === root.requestKey) root.apply(data);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.innerRadius
        color: Theme.paneGlass
        border.width: 1
        border.color: root.paneFocused ? Theme.focusRing : Theme.glassBorder
        Behavior on border.color { ColorAnimation { duration: 160 } }
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: root.status !== "idle"

                Text {
                    Layout.fillWidth: true
                    text: root.signature
                    color: Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    font.family: Theme.monoFamily
                }

                Rectangle {
                    visible: root.symbolType.length > 0
                    radius: 7
                    color: Qt.alpha(Theme.typeColor(root.symbolType), 0.2)
                    border.width: 1
                    border.color: Qt.alpha(Theme.typeColor(root.symbolType), 0.6)
                    implicitWidth: typeLabel.implicitWidth + 14
                    implicitHeight: 20
                    Layout.alignment: Qt.AlignTop
                    Text {
                        id: typeLabel
                        anchors.centerIn: parent
                        text: root.symbolType
                        color: Theme.typeColor(root.symbolType)
                        font.pixelSize: 10
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.status !== "idle"

                Text {
                    Layout.fillWidth: true
                    text: (root.pageTitle.length > 0 ? root.pageTitle + "  ·  " : "") + root.symbolPath.replace(/#.*$/, "")
                    color: Theme.muted
                    elide: Text.ElideMiddle
                    font.pixelSize: 10
                    font.family: Theme.fontFamily
                }

                Rectangle {
                    radius: 6
                    color: openMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Theme.glassBorder
                    implicitWidth: openLabel.implicitWidth + 12
                    implicitHeight: 18
                    Text {
                        id: openLabel
                        anchors.centerIn: parent
                        text: "open in browser ↗"
                        color: Theme.subtext
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                    }
                    MouseArea {
                        id: openMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openInBrowser()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.glassBorder
                visible: root.status !== "idle"
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: root.status !== "ready"
                    color: root.status === "error" ? Theme.rose : Theme.muted
                    font.pixelSize: 13
                    font.family: Theme.fontFamily
                    text: {
                        if (root.status === "idle") return "Start typing to search";
                        if (root.status === "loading") return "Loading…";
                        if (root.status === "empty") return "This entry has no description on its page.\nCtrl+O opens the full page in your browser.";
                        return root.message;
                    }
                }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: body.implicitHeight + 8
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    visible: root.status === "ready"

                    Behavior on contentY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Text {
                        id: body
                        width: flick.width - 6
                        text: root.bodyHtml
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        color: Theme.text
                        linkColor: Theme.link
                        font.pixelSize: Theme.bodyFontSize
                        font.family: Theme.fontFamily
                        lineHeight: Theme.bodyLineHeight
                        activeFocusOnTab: false

                        onLinkActivated: function(link) { root.navigate(link); }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            cursorShape: body.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }

                        Keys.onPressed: function(e) {
                            const ctrl = e.modifiers & Qt.ControlModifier;
                            if (e.key === Qt.Key_Down || (ctrl && e.key === Qt.Key_J)) { root.scrollBy(0.2); e.accepted = true; }
                            else if (e.key === Qt.Key_Up || (ctrl && e.key === Qt.Key_K)) { root.scrollBy(-0.2); e.accepted = true; }
                            else if (e.key === Qt.Key_PageDown || e.key === Qt.Key_Space) { root.scrollBy(1); e.accepted = true; }
                            else if (e.key === Qt.Key_PageUp) { root.scrollBy(-1); e.accepted = true; }
                            else if (e.key === Qt.Key_Home) { flick.contentY = 0; e.accepted = true; }
                            else if (e.key === Qt.Key_End) { flick.contentY = Math.max(0, flick.contentHeight - flick.height); e.accepted = true; }
                            else if (ctrl && e.key === Qt.Key_O) { root.openInBrowser(); e.accepted = true; }
                            else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Tab || e.key === Qt.Key_Backspace) { root.focusInput(); e.accepted = true; }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.12)
                    visible: flick.visible && flick.contentHeight > flick.height
                    height: parent.height
                    Rectangle {
                        width: parent.width
                        radius: parent.radius
                        color: Qt.rgba(1, 1, 1, 0.55)
                        height: Math.max(18, parent.height * flick.height / Math.max(1, flick.contentHeight))
                        y: (parent.height - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
                    }
                }
            }

            Text {
                visible: root.truncated && root.status === "ready"
                Layout.fillWidth: true
                text: "Section truncated — Ctrl+O for the full page"
                color: Theme.muted
                font.pixelSize: 10
                font.family: Theme.fontFamily
            }
        }
    }
}
