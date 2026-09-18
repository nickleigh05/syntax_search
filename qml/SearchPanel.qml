import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "."

Item {
    id: root

    required property string backend
    signal requestHide()

    property var allSymbols: []
    property string docsetName: ""
    property string docsetTitle: ""
    property string docsetIcon: ""
    property string docsDir: ""
    property string status: "loading"
    property string message: ""
    property string pendingQuery: ""
    property int maxResults: 150
    property var availableTypes: []
    property var typeFilter: ({})
    readonly property int typeFilterCount: Object.keys(typeFilter).length

    function grabFocus() {
        applyFocus();
        focusTimer.restart();
        focusRetryTimer.restart();
    }

    function applyFocus() {
        if (docsetMenu.open) docsetMenu.grabFocus();
        else if (typeMenu.open) typeMenu.grabFocus();
        else searchInput.forceActiveFocus();
    }

    function openDocsetMenu() {
        typeMenu.open = false;
        docsetMenu.open = true;
        docsetMenu.grabFocus();
    }

    function openTypeMenu() {
        docsetMenu.open = false;
        typeMenu.open = true;
        typeMenu.grabFocus();
    }

    function typeFilterLabel() {
        const keys = Object.keys(typeFilter);
        if (keys.length === 0) return "All types";
        if (keys.length <= 2) return keys.join(", ");
        return keys.length + " types";
    }

    function computeTypes(symbols) {
        const counts = {};
        for (let i = 0; i < symbols.length; i++) counts[symbols[i][1]] = (counts[symbols[i][1]] || 0) + 1;
        const out = Object.keys(counts).map(k => ({ name: k, count: counts[k] }));
        out.sort((a, b) => (b.count - a.count) || a.name.localeCompare(b.name));
        return out;
    }

    function reloadSymbols() {
        status = "loading";
        symbolLoader.running = false;
        symbolLoader.running = true;
    }

    Component.onCompleted: {
        reloadSymbols();
        grabFocus();
    }

    Timer { id: focusTimer; interval: 30; onTriggered: root.applyFocus() }
    Timer { id: focusRetryTimer; interval: 250; onTriggered: root.applyFocus() }

    Timer {
        id: filterDebounce
        interval: 60
        onTriggered: root.executeFilter(root.pendingQuery)
    }

    Process {
        id: symbolLoader
        command: ["python3", root.backend, "--symbols"]
        stdout: StdioCollector {
            onStreamFinished: root.handleSymbolPayload(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0) console.warn("[syntax-search] backend:", this.text.trim());
            }
        }
        onExited: function(code) {
            if (root.status === "loading" && code !== 0) {
                root.status = "error";
                root.message = "Backend exited with code " + code;
            }
        }
    }

    property string pendingDocset: ""

    Process {
        id: docsetSetter
        command: ["python3", root.backend, "--set-active", root.pendingDocset]
        onExited: function(code) {
            if (code === 0) {
                detail.reset();
                root.reloadSymbols();
            } else {
                root.status = "error";
                root.message = "Failed to switch docset";
            }
        }
    }

    function handleSymbolPayload(text) {
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            status = "error";
            message = "Could not parse backend output";
            return;
        }
        if (data.status === "no_docsets") {
            status = "no_docsets";
            message = data.docsetsDir;
            allSymbols = [];
            availableTypes = [];
            resultModel.clear();
            detail.reset();
            return;
        }
        if (data.status !== "ok") {
            status = "error";
            message = data.message || "Unknown backend error";
            return;
        }
        docsetName = data.docset;
        docsetTitle = data.title || data.docset;
        docsetIcon = data.icon || "";
        docsDir = data.docsDir;
        allSymbols = data.symbols;
        availableTypes = computeTypes(allSymbols);
        const valid = {};
        for (let i = 0; i < availableTypes.length; i++) valid[availableTypes[i].name] = true;
        const kept = {};
        for (const k in typeFilter) if (valid[k]) kept[k] = true;
        typeFilter = kept;
        status = "ready";
        executeFilter(searchInput.text);
    }

    ListModel { id: resultModel }

    function scoreToken(token, nameLower) {
        if (nameLower === token) return 100000;
        if (nameLower.startsWith(token)) return 50000 - nameLower.length;
        const idx = nameLower.indexOf(token);
        if (idx >= 0) {
            const boundary = idx > 0 && /[^a-z0-9]/.test(nameLower[idx - 1]);
            return (boundary ? 20000 : 10000) - idx;
        }
        let i = 0, j = 0, first = -1;
        while (i < token.length && j < nameLower.length) {
            if (token[i] === nameLower[j]) {
                if (first < 0) first = j;
                i++;
            }
            j++;
        }
        if (i !== token.length) return -1;
        return 1000 - (j - first);
    }

    readonly property var proseTypes: ({ "section": true, "guide": true, "sample": true, "option": true, "word": true, "tag": true })

    function lastSegment(nameLower) {
        const parts = nameLower.split(/[.:/#\s]+/).filter(p => p.length > 0);
        return parts.length > 1 ? parts[parts.length - 1] : nameLower;
    }

    function scoreSymbol(token, nameLower, segment) {
        const full = scoreToken(token, nameLower);
        if (full >= 100000) return full + 10000;
        if (segment === nameLower) return full;
        let seg = scoreToken(token, segment);
        if (seg >= 50000) seg += 4000;
        return Math.max(full, seg);
    }

    function executeFilter(query) {
        const tokens = query.toLowerCase().trim().split(/\s+/).filter(t => t.length > 0);
        const results = [];
        const useFilter = typeFilterCount > 0;

        if (tokens.length > 0) {
            for (let i = 0; i < allSymbols.length; i++) {
                const s = allSymbols[i];
                if (useFilter && !typeFilter[s[1]]) continue;
                const nameLower = s[0].toLowerCase();
                const segment = lastSegment(nameLower);
                let total = 0;
                let ok = true;
                for (let t = 0; t < tokens.length; t++) {
                    const sc = scoreSymbol(tokens[t], nameLower, segment);
                    if (sc < 0) { ok = false; break; }
                    total += sc;
                }
                if (!ok) continue;
                if (proseTypes[s[1].toLowerCase()]) total -= 6000;
                results.push({ name: s[0], type: s[1], path: s[2], score: total });
            }
            results.sort((a, b) => (b.score - a.score) || (a.name.length - b.name.length) || a.name.localeCompare(b.name));
            if (results.length > maxResults) results.length = maxResults;
        }

        reconcile(results);
        resultList.currentIndex = resultModel.count > 0 ? 0 : -1;
        syncDetail();
    }

    function itemKey(item) {
        return item.type + "\u0000" + item.name + "\u0000" + item.path;
    }

    function reconcile(items) {
        const wanted = {};
        for (let i = 0; i < items.length; i++) wanted[itemKey(items[i])] = true;
        for (let i = resultModel.count - 1; i >= 0; i--) {
            if (!wanted[itemKey(resultModel.get(i))]) resultModel.remove(i);
        }
        for (let i = 0; i < items.length; i++) {
            const key = itemKey(items[i]);
            if (i < resultModel.count && itemKey(resultModel.get(i)) === key) continue;
            let found = -1;
            for (let j = i + 1; j < resultModel.count; j++) {
                if (itemKey(resultModel.get(j)) === key) { found = j; break; }
            }
            if (found >= 0) resultModel.move(found, i, 1);
            else resultModel.insert(i, items[i]);
        }
        while (resultModel.count > items.length) resultModel.remove(resultModel.count - 1);
    }

    function syncDetail() {
        const idx = resultList.currentIndex;
        if (idx < 0 || idx >= resultModel.count) {
            detail.reset();
            return;
        }
        const item = resultModel.get(idx);
        detail.show(item.name, item.type, item.path);
    }

    function switchDocset(name) {
        if (!name || name === docsetName) return;
        pendingDocset = name;
        docsetSetter.running = false;
        docsetSetter.running = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: 10

        Rectangle {
            id: inputBox
            Layout.fillWidth: true
            height: 46
            radius: Theme.innerRadius
            color: Theme.inputGlass
            border.width: 1
            border.color: searchInput.activeFocus ? Theme.focusRing : Theme.glassBorder
            Behavior on border.color { ColorAnimation { duration: 160 } }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 4
                border.color: Theme.accent
                opacity: searchInput.activeFocus ? 0.08 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 10

                Text {
                    text: "⌕"
                    color: Theme.accent
                    font.pixelSize: 20
                    font.family: Theme.fontFamily
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    selectionColor: Theme.accent
                    selectedTextColor: "#111"
                    font.pixelSize: 15
                    font.family: Theme.fontFamily
                    clip: true
                    focus: true

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: searchInput.text.length === 0
                        text: {
                            if (root.status === "ready") return "Search " + root.docsetTitle + "…";
                            if (root.status === "loading") return "Loading…";
                            return "Press Tab to pick a docset";
                        }
                        color: Theme.muted
                        font: searchInput.font
                    }

                    onTextChanged: {
                        root.pendingQuery = text;
                        filterDebounce.restart();
                    }

                    Keys.onDownPressed: function(e) { resultList.move(1); e.accepted = true; }
                    Keys.onUpPressed: function(e) { resultList.move(-1); e.accepted = true; }
                    Keys.onPressed: function(e) {
                        const ctrl = e.modifiers & Qt.ControlModifier;
                        if (e.key === Qt.Key_PageDown) { detail.scrollBy(1); e.accepted = true; }
                        else if (e.key === Qt.Key_PageUp) { detail.scrollBy(-1); e.accepted = true; }
                        else if (e.key === Qt.Key_Tab) { root.openDocsetMenu(); e.accepted = true; }
                        else if (ctrl && e.key === Qt.Key_T) { root.openTypeMenu(); e.accepted = true; }
                        else if (ctrl && (e.key === Qt.Key_N || e.key === Qt.Key_J)) { resultList.move(1); e.accepted = true; }
                        else if (ctrl && (e.key === Qt.Key_P || e.key === Qt.Key_K)) { resultList.move(-1); e.accepted = true; }
                        else if (ctrl && e.key === Qt.Key_O) { detail.openInBrowser(); e.accepted = true; }
                    }
                    Keys.onReturnPressed: function(e) { detail.focusPane(); e.accepted = true; }
                    Keys.onEnterPressed: function(e) { detail.focusPane(); e.accepted = true; }
                    Keys.onEscapePressed: function(e) { root.requestHide(); e.accepted = true; }
                }

                Rectangle {
                    id: typePill
                    radius: 9
                    color: typePillMouse.containsMouse || typeMenu.open ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: root.typeFilterCount > 0 ? Theme.selectionBorder : Theme.glassBorder
                    implicitWidth: typePillRow.implicitWidth + 20
                    implicitHeight: 30
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: typePillRow
                        anchors.centerIn: parent
                        spacing: 6
                        Repeater {
                            model: Object.keys(root.typeFilter).slice(0, 3)
                            delegate: Rectangle {
                                required property string modelData
                                width: 8
                                height: 8
                                radius: 4
                                color: Theme.typeColor(modelData)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            text: root.typeFilterLabel()
                            color: root.typeFilterCount > 0 ? Theme.text : Theme.subtext
                            font.pixelSize: 12
                            font.weight: root.typeFilterCount > 0 ? Font.DemiBold : Font.Normal
                            font.family: Theme.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "▾"
                            color: Theme.subtext
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                            rotation: typeMenu.open ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 140 } }
                        }
                    }

                    MouseArea {
                        id: typePillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: typeMenu.open ? typeMenu.close() : root.openTypeMenu()
                    }
                }

                Rectangle {
                    id: docsetPill
                    radius: 9
                    color: pillMouse.containsMouse || docsetMenu.open ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: Theme.selectionBorder
                    implicitWidth: pillRow.implicitWidth + 20
                    implicitHeight: 30
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 7
                        Image {
                            visible: root.docsetIcon.length > 0
                            source: root.docsetIcon.length > 0 ? "file://" + root.docsetIcon : ""
                            width: 16
                            height: 16
                            sourceSize: Qt.size(32, 32)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.docsetTitle || "No docset"
                            color: Theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.family: Theme.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "▾"
                            color: Theme.subtext
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                            rotation: docsetMenu.open ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 140 } }
                        }
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: docsetMenu.open ? docsetMenu.close() : root.openDocsetMenu()
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Item {
                Layout.preferredWidth: Theme.listWidth
                Layout.fillHeight: true
                clip: true

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 6
                    visible: root.status !== "ready" || resultModel.count === 0

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: root.status === "error" ? Theme.rose : Theme.subtext
                        font.pixelSize: 13
                        font.family: Theme.fontFamily
                        text: {
                            if (root.status === "loading") return "Indexing symbols…";
                            if (root.status === "no_docsets") return "No docsets found";
                            if (root.status === "error") return root.message;
                            if (root.pendingQuery.trim().length === 0) return "";
                            return "No matches";
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.status === "no_docsets"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Theme.muted
                        font.pixelSize: 10
                        font.family: Theme.monoFamily
                        text: "Install docsets with Zeal, or set SYNTAX_SEARCH_DOCSETS.\nLooked in: " + root.message
                    }
                }

                ResultList {
                    id: resultList
                    anchors.fill: parent
                    model: resultModel
                    visible: root.status === "ready" && resultModel.count > 0
                    onCurrentIndexChanged: root.syncDetail()
                    onActivated: detail.focusPane()
                }
            }

            DetailPane {
                id: detail
                Layout.fillWidth: true
                Layout.fillHeight: true
                backend: root.backend
                docsetName: root.docsetName
                onFocusInput: searchInput.forceActiveFocus()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Repeater {
                model: [["↑↓", "select"], ["↵", "read"], ["PgUp/PgDn", "scroll"], ["Ctrl+T", "types"], ["Tab", "docset"], ["Ctrl+O", "browser"], ["Esc", "hide"]]
                delegate: RowLayout {
                    required property var modelData
                    spacing: 5
                    Rectangle {
                        radius: 5
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        border.color: Theme.glassBorder
                        implicitWidth: keyText.implicitWidth + 10
                        implicitHeight: 18
                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: parent.parent.modelData[0]
                            color: Theme.subtext
                            font.pixelSize: 10
                            font.family: Theme.fontFamily
                        }
                    }
                    Text {
                        text: parent.modelData[1]
                        color: Theme.muted
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: root.status === "ready"
                text: resultModel.count + " / " + root.allSymbols.length
                color: Theme.muted
                font.pixelSize: 10
                font.family: Theme.monoFamily
            }
        }
    }

    TypeFilterMenu {
        id: typeMenu
        types: root.availableTypes
        selected: root.typeFilter
        x: inputBox.x + inputBox.width - docsetPill.width - 10 - width
        y: inputBox.y + inputBox.height + 6
        z: 100
        onChanged: function(sel) {
            root.typeFilter = sel;
            root.executeFilter(searchInput.text);
        }
        onClosed: searchInput.forceActiveFocus()
    }

    DocsetMenu {
        id: docsetMenu
        backend: root.backend
        activeName: root.docsetName
        x: inputBox.x + inputBox.width - width
        y: inputBox.y + inputBox.height + 6
        z: 100
        onChosen: function(name) { root.switchDocset(name); }
        onClosed: searchInput.forceActiveFocus()
    }
}
