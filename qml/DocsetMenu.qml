import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "."

Item {
    id: root

    required property string backend
    property string activeName: ""
    property bool open: false
    property var docsets: []
    property string status: "loading"

    signal chosen(string name)
    signal closed()

    width: 300
    height: open ? Math.min(340, 52 + Math.max(1, listModel.count) * (Theme.rowHeight - 6 + 4) + 16) : 0
    visible: open || heightAnim.running
    clip: true
    opacity: open ? 1 : 0

    Behavior on height { NumberAnimation { id: heightAnim; duration: 140; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 120 } }

    onOpenChanged: {
        if (open) {
            filterInput.text = "";
            status = "loading";
            lister.running = false;
            lister.running = true;
        }
    }

    function grabFocus() {
        filterInput.forceActiveFocus();
    }

    function close() {
        open = false;
        closed();
    }

    Process {
        id: lister
        command: ["python3", root.backend, "--list-docsets"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data;
                try { data = JSON.parse(this.text); } catch (e) {
                    root.status = "error";
                    return;
                }
                root.docsets = data.docsets || [];
                root.status = root.docsets.length > 0 ? "ready" : "no_docsets";
                root.applyFilter(filterInput.text);
            }
        }
    }

    ListModel { id: listModel }

    function applyFilter(query) {
        const q = query.toLowerCase().trim();
        listModel.clear();
        let selected = 0;
        for (let i = 0; i < docsets.length; i++) {
            const d = docsets[i];
            const title = d.title || d.name;
            const hay = (title + " " + d.name).toLowerCase();
            let ok = q.length === 0 || hay.includes(q);
            if (!ok) {
                let a = 0;
                for (let j = 0; j < hay.length && a < q.length; j++) if (hay[j] === q[a]) a++;
                ok = a === q.length;
            }
            if (!ok) continue;
            if (d.name === activeName) selected = listModel.count;
            listModel.append({ name: d.name, title: title, version: d.version || "", icon: d.icon || "", isActive: d.name === activeName });
        }
        list.currentIndex = listModel.count > 0 ? selected : -1;
    }

    function choose(index) {
        if (index < 0 || index >= listModel.count) return;
        const name = listModel.get(index).name;
        open = false;
        chosen(name);
        closed();
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.innerRadius
        color: Theme.menuGlass
        border.width: 1
        border.color: Qt.alpha(Theme.accentAlt, 0.45)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: 8
                color: Theme.inputGlass
                border.width: 1
                border.color: filterInput.activeFocus ? Theme.accentAlt : Theme.glassBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Text {
                        text: "⇆"
                        color: Theme.accentAlt
                        font.pixelSize: 14
                        font.family: Theme.fontFamily
                    }
                    TextInput {
                        id: filterInput
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        selectionColor: Theme.accentAlt
                        selectedTextColor: "#111"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        clip: true

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: filterInput.text.length === 0
                            text: "Choose a docset…"
                            color: Theme.muted
                            font: filterInput.font
                        }

                        onTextChanged: root.applyFilter(text)

                        Keys.onDownPressed: function(e) { if (listModel.count > 0) list.currentIndex = Math.min(listModel.count - 1, list.currentIndex + 1); e.accepted = true; }
                        Keys.onUpPressed: function(e) { if (listModel.count > 0) list.currentIndex = Math.max(0, list.currentIndex - 1); e.accepted = true; }
                        Keys.onPressed: function(e) {
                            const ctrl = e.modifiers & Qt.ControlModifier;
                            if (ctrl && (e.key === Qt.Key_N || e.key === Qt.Key_J)) { list.currentIndex = Math.min(listModel.count - 1, list.currentIndex + 1); e.accepted = true; }
                            else if (ctrl && (e.key === Qt.Key_P || e.key === Qt.Key_K)) { list.currentIndex = Math.max(0, list.currentIndex - 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Tab) { root.close(); e.accepted = true; }
                        }
                        Keys.onReturnPressed: function(e) { root.choose(list.currentIndex); e.accepted = true; }
                        Keys.onEnterPressed: function(e) { root.choose(list.currentIndex); e.accepted = true; }
                        Keys.onEscapePressed: function(e) { root.close(); e.accepted = true; }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.status !== "ready" || listModel.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.subtext
                font.pixelSize: 12
                font.family: Theme.fontFamily
                text: {
                    if (root.status === "loading") return "Scanning…";
                    if (root.status === "no_docsets") return "No docsets installed";
                    if (root.status === "error") return "Failed to list docsets";
                    return "No matches";
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: listModel
                spacing: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                highlightFollowsCurrentItem: false
                visible: root.status === "ready" && listModel.count > 0

                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

                Rectangle {
                    parent: list.contentItem
                    z: 0
                    width: list.width
                    height: Theme.rowHeight - 6
                    radius: 8
                    visible: list.currentItem !== null
                    y: list.currentItem ? list.currentItem.y : 0
                    Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    color: Qt.alpha(Theme.accentAlt, 0.22)
                    border.width: 1
                    border.color: Qt.alpha(Theme.accentAlt, 0.6)
                }

                delegate: Item {
                    id: row
                    required property int index
                    required property string name
                    required property string title
                    required property string version
                    required property string icon
                    required property bool isActive

                    width: ListView.view.width
                    height: Theme.rowHeight - 6
                    z: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Item {
                            width: 18
                            height: 18
                            Image {
                                anchors.fill: parent
                                visible: row.icon.length > 0
                                source: row.icon.length > 0 ? "file://" + row.icon : ""
                                sourceSize: Qt.size(36, 36)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: row.icon.length === 0
                                width: 9
                                height: 9
                                radius: 4.5
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.muted
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.title
                            color: Theme.text
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            font.family: Theme.fontFamily
                            font.weight: row.isActive ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            visible: row.version.length > 0
                            text: row.version
                            color: Theme.muted
                            font.pixelSize: 10
                            font.family: Theme.monoFamily
                        }
                        Rectangle {
                            visible: row.isActive
                            width: 7
                            height: 7
                            radius: 3.5
                            color: Theme.green
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choose(row.index)
                    }
                }
            }
        }
    }
}
