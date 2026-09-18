import QtQuick
import QtQuick.Layouts
import "."

Item {
    id: root

    property var types: []
    property var selected: ({})
    property bool open: false

    signal changed(var selected)
    signal closed()

    readonly property int selectedCount: Object.keys(selected).length

    width: 300
    height: open ? Math.min(400, 52 + (listModel.count + 1) * (Theme.rowHeight - 8 + 4) + 16) : 0
    visible: open || heightAnim.running
    clip: true
    opacity: open ? 1 : 0

    Behavior on height { NumberAnimation { id: heightAnim; duration: 140; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 120 } }

    onOpenChanged: {
        if (open) {
            filterInput.text = "";
            rebuild("");
        }
    }

    onTypesChanged: if (open) rebuild(filterInput.text)

    function grabFocus() {
        filterInput.forceActiveFocus();
    }

    function close() {
        open = false;
        closed();
    }

    ListModel { id: listModel }

    function rebuild(query) {
        const q = query.toLowerCase().trim();
        listModel.clear();
        for (let i = 0; i < types.length; i++) {
            const t = types[i];
            if (q.length > 0 && !t.name.toLowerCase().includes(q)) continue;
            listModel.append({ name: t.name, count: t.count, checked: Boolean(selected[t.name]) });
        }
        list.currentIndex = listModel.count > 0 ? 0 : -1;
    }

    function toggle(index) {
        if (index < 0 || index >= listModel.count) return;
        const item = listModel.get(index);
        const next = Object.assign({}, selected);
        if (next[item.name]) delete next[item.name]; else next[item.name] = true;
        selected = next;
        listModel.setProperty(index, "checked", Boolean(next[item.name]));
        changed(selected);
    }

    function clearAll() {
        selected = ({});
        for (let i = 0; i < listModel.count; i++) listModel.setProperty(i, "checked", false);
        changed(selected);
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.innerRadius
        color: Theme.menuGlass
        border.width: 1
        border.color: Theme.selectionBorder

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
                border.color: filterInput.activeFocus ? Theme.focusRing : Theme.glassBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Text {
                        text: "☑"
                        color: Theme.text
                        font.pixelSize: 14
                        font.family: Theme.fontFamily
                    }
                    TextInput {
                        id: filterInput
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: "#111"
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        clip: true

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: filterInput.text.length === 0
                            text: "Filter symbol types…"
                            color: Theme.muted
                            font: filterInput.font
                        }

                        onTextChanged: root.rebuild(text)

                        Keys.onDownPressed: function(e) { if (listModel.count > 0) list.currentIndex = Math.min(listModel.count - 1, list.currentIndex + 1); e.accepted = true; }
                        Keys.onUpPressed: function(e) { if (listModel.count > 0) list.currentIndex = Math.max(0, list.currentIndex - 1); e.accepted = true; }
                        Keys.onPressed: function(e) {
                            const ctrl = e.modifiers & Qt.ControlModifier;
                            if (ctrl && (e.key === Qt.Key_N || e.key === Qt.Key_J)) { list.currentIndex = Math.min(listModel.count - 1, list.currentIndex + 1); e.accepted = true; }
                            else if (ctrl && (e.key === Qt.Key_P || e.key === Qt.Key_K)) { list.currentIndex = Math.max(0, list.currentIndex - 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Space && filterInput.text.length === 0) { root.toggle(list.currentIndex); e.accepted = true; }
                            else if (ctrl && e.key === Qt.Key_Backspace) { root.clearAll(); e.accepted = true; }
                            else if (e.key === Qt.Key_Tab || (ctrl && e.key === Qt.Key_T)) { root.close(); e.accepted = true; }
                        }
                        Keys.onReturnPressed: function(e) { root.toggle(list.currentIndex); e.accepted = true; }
                        Keys.onEnterPressed: function(e) { root.toggle(list.currentIndex); e.accepted = true; }
                        Keys.onEscapePressed: function(e) { root.close(); e.accepted = true; }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: Theme.rowHeight - 12
                radius: 8
                color: clearMouse.containsMouse ? Theme.hover : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    Text {
                        Layout.fillWidth: true
                        text: root.selectedCount === 0 ? "All types shown" : "Clear " + root.selectedCount + " selected"
                        color: root.selectedCount === 0 ? Theme.muted : Theme.text
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: "Ctrl+⌫"
                        color: Theme.muted
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                        visible: root.selectedCount > 0
                    }
                }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.selectedCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.clearAll()
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

                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

                Rectangle {
                    parent: list.contentItem
                    z: 0
                    width: list.width
                    height: Theme.rowHeight - 8
                    radius: 8
                    visible: list.currentItem !== null
                    y: list.currentItem ? list.currentItem.y : 0
                    Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    color: Theme.selectionStart
                    border.width: 1
                    border.color: Theme.selectionBorder
                }

                delegate: Item {
                    id: row
                    required property int index
                    required property string name
                    required property int count
                    required property bool checked
                    readonly property color badge: Theme.typeColor(name)

                    width: ListView.view.width
                    height: Theme.rowHeight - 8
                    z: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 4
                            color: row.checked ? row.badge : "transparent"
                            border.width: 1.5
                            border.color: row.checked ? row.badge : Theme.muted
                            Text {
                                anchors.centerIn: parent
                                visible: row.checked
                                text: "✓"
                                color: "#111"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                        Rectangle {
                            width: 4
                            height: 18
                            radius: 2
                            color: row.badge
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.name
                            color: Theme.text
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            font.family: Theme.fontFamily
                            font.weight: row.checked ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            text: row.count
                            color: Theme.muted
                            font.pixelSize: 11
                            font.family: Theme.monoFamily
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { list.currentIndex = row.index; root.toggle(row.index); }
                    }
                }
            }
        }
    }
}
