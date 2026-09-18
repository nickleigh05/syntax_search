import QtQuick
import QtQuick.Layouts
import "."

ListView {
    id: list

    signal activated()

    spacing: 4
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    highlightFollowsCurrentItem: false
    currentIndex: -1

    function move(delta) {
        if (count === 0) return;
        currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
    }

    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

    Rectangle {
        parent: list.contentItem
        z: 0
        width: list.width
        height: Theme.rowHeight
        radius: Theme.innerRadius
        visible: list.currentItem !== null
        y: list.currentItem ? list.currentItem.y : 0
        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.selectionStart }
            GradientStop { position: 1.0; color: Theme.selectionEnd }
        }
        border.width: 1
        border.color: Theme.selectionBorder
    }

    delegate: Item {
        id: row
        required property int index
        required property string name
        required property string type
        required property string path
        readonly property bool selected: index === list.currentIndex
        readonly property color badge: Theme.typeColor(type)

        width: ListView.view.width
        height: Theme.rowHeight
        z: 1

        Rectangle {
            anchors.fill: parent
            radius: Theme.innerRadius
            color: Theme.hover
            opacity: rowMouse.containsMouse && !row.selected ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                width: 4
                height: 22
                radius: 2
                color: row.badge
                opacity: row.selected ? 1 : 0.7
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.name
                    color: Theme.text
                    elide: Text.ElideMiddle
                    font.pixelSize: 14
                    font.family: Theme.monoFamily
                    font.weight: row.selected ? Font.DemiBold : Font.Normal
                }
                Text {
                    Layout.fillWidth: true
                    text: row.type
                    color: row.selected ? row.badge : Theme.muted
                    elide: Text.ElideRight
                    font.pixelSize: 10
                    font.family: Theme.fontFamily
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: list.currentIndex = row.index
            onDoubleClicked: { list.currentIndex = row.index; list.activated(); }
        }
    }
}
