pragma Singleton
import QtQuick

QtObject {
    readonly property int windowWidth: 1100
    readonly property int windowHeight: 680
    readonly property int listWidth: 340
    readonly property int rowHeight: 48
    readonly property int padding: 16
    readonly property real radius: 18
    readonly property real innerRadius: 10

    readonly property int bodyFontSize: 15
    readonly property real bodyLineHeight: 1.35

    readonly property string fontFamily: "Inter, Noto Sans, sans-serif"
    readonly property string monoFamily: "JetBrainsMono Nerd Font, JetBrains Mono, Fira Code, monospace"

    readonly property color glass: Qt.rgba(0.035, 0.035, 0.045, 0.78)
    readonly property color paneGlass: Qt.rgba(1, 1, 1, 0.025)
    readonly property color menuGlass: Qt.rgba(0.05, 0.05, 0.06, 0.97)
    readonly property color inputGlass: Qt.rgba(1, 1, 1, 0.045)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.09)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.05)
    readonly property string codeBg: "#0f0f12"
    readonly property string codeText: "#dfe3ea"

    readonly property color text: "#f2f2f5"
    readonly property color subtext: "#a6a6b0"
    readonly property color muted: "#6a6a75"

    readonly property color accent: "#ffffff"
    readonly property color accentAlt: accent
    readonly property color selectionStart: Qt.rgba(1, 1, 1, 0.11)
    readonly property color selectionEnd: Qt.rgba(1, 1, 1, 0.11)
    readonly property color selectionBorder: Qt.rgba(1, 1, 1, 0.32)
    readonly property color focusRing: Qt.rgba(1, 1, 1, 0.55)
    readonly property color link: "#cfe2ff"

    readonly property color blue: "#4da3ff"
    readonly property color teal: "#2fe0a8"
    readonly property color pink: "#ff6fb5"
    readonly property color orange: "#ffa047"
    readonly property color green: "#a8f03a"
    readonly property color violet: "#b384ff"
    readonly property color yellow: "#ffe45c"
    readonly property color sky: "#49cdf5"
    readonly property color rose: "#ff5f6d"

    function typeColor(type) {
        switch ((type || "").toLowerCase()) {
        case "function": case "func": case "procedure": case "subroutine": case "macro":
            return blue;
        case "method": case "clm": case "instm": case "intfm": case "clmethod":
            return teal;
        case "class": case "struct": case "union": case "record":
            return pink;
        case "trait": case "interface": case "protocol": case "mixin": case "typedef": case "type": case "enum":
            return orange;
        case "constant": case "variable": case "field": case "property": case "attribute": case "value": case "constructor":
            return green;
        case "module": case "package": case "namespace": case "library": case "crate": case "component":
            return violet;
        case "keyword": case "operator": case "directive": case "statement": case "builtin":
            return yellow;
        case "guide": case "section": case "sample": case "tag": case "element": case "word":
            return sky;
        case "error": case "exception":
            return rose;
        default:
            return subtext;
        }
    }
}
