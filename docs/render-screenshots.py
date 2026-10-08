#!/usr/bin/env python3
"""Render the real plugin pages offscreen, using fictional data only.

Requires Quickshell and the Omarchy shell at /usr/share/omarchy/shell.
The temporary helper never reads credentials or makes network requests.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COURSES = [
    {"id": "101", "name": "Introduction to Design"},
    {"id": "102", "name": "Creative Writing"},
    {"id": "103", "name": "Environmental Science"},
    {"id": "104", "name": "World History"},
]

with tempfile.TemporaryDirectory(prefix="canvas-screenshots-") as directory:
    stage = Path(directory)
    for module in ("Commons", "Ui"):
        (stage / module).symlink_to(Path("/usr/share/omarchy/shell") / module, target_is_directory=True)
    for source in ROOT.glob("Canvas*"):
        shutil.copy2(source, stage / source.name)
    shutil.copy2(ROOT / "Settings.qml", stage / "Settings.qml")
    # Replace only the compositor-specific popup container. Page contents and
    # controls come from the plugin and installed Omarchy shell unchanged.
    panel = (ROOT / "Panel.qml").read_text().replace('    moduleName: "gnussonnet.omarchy-canvas"\n    manageIpc: false\n', "")
    panel = panel.replace('Ui.Panel {', '''Item {
    property var bar: null
    property string moduleName: ""
    property bool manageIpc: false
    property bool opened: true
    property color barForeground: Color.foreground
    function close() {}''', 1)
    panel = panel.replace("Ui.KeyboardPanel {", "ScreenshotCard {", 1)
    (stage / "Panel.qml").write_text(panel)
    (stage / "ScreenshotCard.qml").write_text('''import QtQuick
import qs.Commons
Rectangle {
    property var anchorItem: null
    property var owner: null
    property var bar: null
    property bool open: true
    property int padding: 10
    property int contentWidth: 460
    property int contentHeight: 500
    property Item focusTarget: null
    width: contentWidth + padding * 2 + 4
    height: contentHeight + padding * 2 + 4
    color: Color.popups.background
    border.color: Color.accent
    border.width: 2
    default property alias content: holder.data
    function fittedContentWidth(value) { return value }
    function fittedContentHeight(value) { return value }
    Item { id: holder; anchors.fill: parent; anchors.margins: parent.padding + 2 }
}
''')
    settings = {"ok": True, "configured": True, "url": "https://canvas.example.edu",
                "courses": COURSES, "courses_loaded": True,
                "selected_course_ids": ["101", "102", "103"], "days_ahead": 7,
                "selection_saved": True}
    (stage / "canvas.py").write_text("import json\nprint(json.dumps(" + repr(settings) + "))\n")
    output = ROOT / "docs/screenshots"
    output.mkdir(parents=True, exist_ok=True)
    (stage / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
Window {
    id: window
    visible: true
    width: 484
    height: 524
    color: Color.background
    QtObject {
        id: sample
        property var assignments: [
            {id: "101:1", name: "Sketchbook: everyday objects", course: "Introduction to Design", due_at: "2026-10-08T16:00:00+02:00", status: "Not submitted", url: "https://canvas.example.edu/courses/101/assignments/1"},
            {id: "102:2", name: "Short story: first draft", course: "Creative Writing", due_at: "2026-10-08T18:00:00+02:00", status: "Submitted", url: "https://canvas.example.edu/courses/102/assignments/2"},
            {id: "103:3", name: "Field notes: local biodiversity", course: "Environmental Science", due_at: "2026-10-09T14:00:00+02:00", status: "Not submitted", url: "https://canvas.example.edu/courses/103/assignments/3"},
            {id: "101:4", name: "Color and composition study", course: "Introduction to Design", due_at: "2026-10-12T16:00:00+02:00", status: "Not submitted", url: "https://canvas.example.edu/courses/101/assignments/4"}
        ]
        property int daysAhead: 7
        property int notSubmittedCount: 3
        property int selectedCourseCount: 3
        property bool busy: false
        property bool needsSetup: false
        property string error: ""
        property var warnings: []
        property string updatedAt: "2026-10-08T10:00:00+02:00"
        function cancelRefresh() {}
        function refresh() {}
    }
    Panel { id: page; anchors.fill: parent; hostWidget: sample; now: new Date("2026-10-08T10:00:00+02:00") }
    Timer {
        interval: 1500; running: true
        onTriggered: window.contentItem.grabToImage(function(result) {
            if (!result.saveToFile(OUTPUT + "/assignments.png")) Qt.quit()
            page.openSettings()
            settingsTimer.start()
        }, Qt.size(968, 1048))
    }
    Timer {
        id: settingsTimer; interval: 1500
        onTriggered: window.contentItem.grabToImage(function(result) {
            result.saveToFile(OUTPUT + "/settings.png")
            Qt.quit()
        }, Qt.size(968, 1048))
    }
}
'''.replace("OUTPUT", json.dumps(str(output))))
    env = dict(os.environ, HOME=str(stage), XDG_CONFIG_HOME=str(stage / "config"),
               XDG_CACHE_HOME=str(stage / "cache"), XDG_DATA_HOME=str(stage / "data"),
               XDG_RUNTIME_DIR=str(stage), QT_QPA_PLATFORM="offscreen",
               QT_QPA_PLATFORMTHEME="generic", QT_QUICK_BACKEND="software", TZ="Europe/Stockholm")
    subprocess.run(["qs", "--no-color", "-p", str(stage / "shell.qml")], env=env,
                   check=True, timeout=25)
    for name in ("assignments.png", "settings.png"):
        if not (output / name).is_file():
            raise RuntimeError(f"Screenshot was not created: {name}")
    print("Saved fictional-data screenshots to", output)
