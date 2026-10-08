import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell-todo"
    // Bottom layer: desktop view only (sits directly on wallpaper, behind normal windows)
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        right: true
    }
    
    margins {
        top: 56
        right: 28
    }

    implicitWidth: 360
    implicitHeight: mainCard.height

    color: "transparent"

    mask: Region {
        x: mainCard.x
        y: mainCard.y
        width: mainCard.width
        height: mainCard.height
    }

    // Theme Palette (Catppuccin Mocha Tonalspot)
    readonly property color colSurface: "#801e1d22"
    readonly property color colSurfaceLow: "#80161519"
    readonly property color colSurfaceHigh: "#992a292e"
    readonly property color colSurfaceHighest: "#99353438"
    readonly property color colText: "#e5e1e7"
    readonly property color colTextVariant: "#c8c5d1"
    readonly property color colOutline: "#47464f"
    readonly property color colOutlineVariant: "#333238"
    readonly property color colPrimary: "#c2c1ff"
    readonly property color colTextOnPrimary: "#2a2a60"
    readonly property color colTertiary: "#f5b2e0"
    readonly property color colSuccess: "#B5CCBA"
    readonly property color colError: "#ffb4ab"

    // Primary Tab: "tasks" | "agenda"
    property string currentMainTab: "tasks"

    // Tasks State
    property bool nextTaskIsDaily: false
    property string activeFilter: "all"     // "all" | "active" | "done"
    property var masterList: []
    property string lastResetDate: ""

    // Agenda State
    property string agendaFilter: "today" // "today" | "upcoming" | "all"
    property var allEvents: []
    property string selectedEventDate: getTodayString()
    property string selectedEventDateLabel: "Today"
    property string selectedEventTime: "All Day"
    property bool dateTimeSelectorOpen: false
    property bool calendarSettingsOpen: false
    property string savedIcalUrl: ""

    Shortcut {
        sequence: "Ctrl+R"
        enabled: root.currentMainTab === "tasks"
        onActivated: {
            root.nextTaskIsDaily = !root.nextTaskIsDaily
            inputField.forceActiveFocus()
        }
    }

    function getTodayString() {
        var d = new Date()
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, '0') + "-" + String(d.getDate()).padStart(2, '0')
    }

    function getUpcomingDays() {
        var list = []
        var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var now = new Date()
        for (var i = 0; i < 8; i++) {
            var d = new Date(now.getTime() + i * 24 * 60 * 60 * 1000)
            var yyyy = d.getFullYear()
            var mm = String(d.getMonth() + 1).padStart(2, '0')
            var dd = String(d.getDate()).padStart(2, '0')
            var iso = yyyy + "-" + mm + "-" + dd
            var label = i === 0 ? "Today" : (i === 1 ? "Tomorrow" : (dayNames[d.getDay()] + " " + d.getDate()))
            list.push({ "iso": iso, "label": label })
        }
        return list
    }

    // Midnight rollover & periodic check timer (checks every 30 seconds)
    Timer {
        id: dayRolloverTimer
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.checkDayRollover()
    }

    // --- Process Handlers for Tasks ---
    Process {
        id: initFile
        command: ["bash", "-c", "mkdir -p ~/.local/state && touch ~/.local/state/todos.json"]
        running: true
        onExited: {
            readProc.running = true
            syncCalendarProc.running = true
            readCalendarConfigProc.running = true
        }
    }

    Process {
        id: readProc
        command: ["bash", "-c", "cat ~/.local/state/todos.json | tr -d '\n'"]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(data)
                        var curDate = root.getTodayString()
                        var rawList = []
                        var fileResetDate = ""

                        if (Array.isArray(parsed)) {
                            rawList = parsed
                            fileResetDate = ""
                        } else if (parsed && typeof parsed === "object") {
                            fileResetDate = parsed.lastResetDate || ""
                            if (Array.isArray(parsed.tasks)) {
                                rawList = parsed.tasks
                            } else if (Array.isArray(parsed.master)) {
                                rawList = parsed.master
                            } else {
                                if (Array.isArray(parsed.today)) {
                                    rawList = rawList.concat(parsed.today.map(t => ({ text: t.text, done: t.done, type: "today", lastCompletedDate: t.lastCompletedDate || "" })))
                                }
                                if (Array.isArray(parsed.daily)) {
                                    rawList = rawList.concat(parsed.daily.map(t => ({ text: t.text, done: t.done, type: "daily", lastCompletedDate: t.lastCompletedDate || "" })))
                                }
                            }
                        }

                        var isDifferentDay = (fileResetDate !== "" && fileResetDate !== curDate)
                        var isLegacyFile = (fileResetDate === "")
                        var list = []

                        for (var i = 0; i < rawList.length; i++) {
                            var item = rawList[i]
                            var textVal = item.text || item
                            var typeVal = item.type || "today"
                            var doneVal = !!item.done
                            var lastComp = item.lastCompletedDate || ""

                            if (typeVal === "daily") {
                                if (doneVal) {
                                    if (lastComp && lastComp !== curDate) {
                                        doneVal = false
                                        lastComp = ""
                                    } else if (!lastComp && (isDifferentDay || isLegacyFile)) {
                                        doneVal = false
                                        lastComp = ""
                                    }
                                }
                                list.push({
                                    text: textVal,
                                    done: doneVal,
                                    type: "daily",
                                    lastCompletedDate: lastComp
                                })
                            } else {
                                if ((isDifferentDay || isLegacyFile) && doneVal && lastComp && lastComp !== curDate) {
                                    // prune completed one-off task from previous day
                                } else {
                                    list.push({
                                        text: textVal,
                                        done: doneVal,
                                        type: "today",
                                        lastCompletedDate: lastComp
                                    })
                                }
                            }
                        }

                        root.masterList = list
                        root.lastResetDate = curDate

                        if (isDifferentDay || isLegacyFile) {
                            root.saveTodos()
                        }
                        root.syncTaskModel()
                    } catch (e) {
                        console.log("Error parsing todos.json: " + e)
                        root.syncTaskModel()
                    }
                } else {
                    root.syncTaskModel()
                }
            }
        }
    }

    Process {
        id: writeProc
        property string content: "{}"
        command: ["bash", "-c", "cat << 'EOF' > ~/.local/state/todos.json\n" + content + "\nEOF"]
    }

    function checkDayRollover() {
        var curDate = getTodayString()
        if (root.lastResetDate === curDate) return

        console.log("[TodoWidget] Date rollover detected! " + root.lastResetDate + " -> " + curDate)
        var changed = false
        var newList = []

        for (var i = 0; i < masterList.length; i++) {
            var t = masterList[i]
            if (t.type === "daily") {
                if (t.done && t.lastCompletedDate !== curDate) {
                    t.done = false
                    t.lastCompletedDate = ""
                    changed = true
                }
                newList.push(t)
            } else {
                if (t.done && root.lastResetDate && root.lastResetDate !== curDate) {
                    changed = true
                } else {
                    newList.push(t)
                }
            }
        }

        root.lastResetDate = curDate
        masterList = newList
        saveTodos()
        syncTaskModel()

        root.selectedEventDate = curDate
        syncCalendarProc.running = true
    }

    function saveTodos() {
        var curDate = getTodayString()
        root.lastResetDate = curDate
        var payload = {
            "lastResetDate": curDate,
            "tasks": masterList
        }
        writeProc.content = JSON.stringify(payload, null, 2)
        writeProc.running = true
    }

    function syncTaskModel() {
        taskModel.clear()
        for (var i = 0; i < masterList.length; i++) {
            var item = masterList[i]
            var matches = true
            if (activeFilter === "active" && item.done) matches = false
            if (activeFilter === "done" && !item.done) matches = false
            if (activeFilter === "daily" && item.type !== "daily") matches = false

            if (matches) {
                taskModel.append({
                    "text": item.text,
                    "done": item.done,
                    "rawIndex": i,
                    "type": item.type || "today"
                })
            }
        }
    }

    function toggleTask(rawIndex) {
        if (rawIndex >= 0 && rawIndex < masterList.length) {
            var curDate = getTodayString()
            var temp = masterList
            var item = temp[rawIndex]
            item.done = !item.done
            if (item.done) {
                item.lastCompletedDate = curDate
            } else {
                item.lastCompletedDate = ""
            }
            masterList = temp
            saveTodos()
            syncTaskModel()
        }
    }

    function toggleRecurring(rawIndex) {
        if (rawIndex >= 0 && rawIndex < masterList.length) {
            var curDate = getTodayString()
            var temp = masterList
            var item = temp[rawIndex]
            item.type = (item.type === "daily") ? "today" : "daily"
            if (item.type === "daily" && item.done && !item.lastCompletedDate) {
                item.lastCompletedDate = curDate
            }
            masterList = temp
            saveTodos()
            syncTaskModel()
        }
    }

    function deleteTask(rawIndex) {
        console.log("deleteTask triggered! rawIndex: " + rawIndex)
        if (rawIndex >= 0 && rawIndex < masterList.length) {
            var temp = masterList
            temp.splice(rawIndex, 1)
            masterList = temp
            saveTodos()
            syncTaskModel()
        }
    }

    function addTask(text, type) {
        console.log("addTask triggered! text: " + text + " type: " + type)
        var temp = masterList
        temp.push({
            "text": text,
            "done": false,
            "type": type,
            "lastCompletedDate": ""
        })
        masterList = temp
        saveTodos()
        syncTaskModel()
    }


    function countPending() {
        var c = 0
        for (var i = 0; i < masterList.length; i++) {
            if (!masterList[i].done) c++
        }
        return c
    }

    // --- Process Handlers for Agenda & Google Calendar ---
    Process {
        id: syncCalendarProc
        command: ["bash", "-c", "for p in \"$HOME/.config/quickshell-todo-widget/calendar_sync.py\" \"/home/zius/Projects/playground/calendar_sync.py\" \"./calendar_sync.py\"; do if [ -f \"$p\" ]; then python3 \"$p\"; exit 0; fi; done"]
        onExited: readEventsProc.running = true
    }

    Process {
        id: readEventsProc
        command: ["bash", "-c", "cat ~/.local/state/calendar_events.json | tr -d '\n'"]
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim().length > 0) {
                    try {
                        root.allEvents = JSON.parse(data)
                        root.syncAgendaModel()
                    } catch (e) {
                        root.syncAgendaModel()
                    }
                } else {
                    root.syncAgendaModel()
                }
            }
        }
    }

    Process {
        id: addLocalEventProc
        property string eventTitle: ""
        property string eventDate: ""
        property string eventTime: ""
        command: [
            "python3", "-c",
            "import json, os, sys, datetime; f=os.path.expanduser('~/.local/state/calendar_local.json'); data=json.load(open(f)) if os.path.exists(f) else []; data.append({'id': int(datetime.datetime.now().timestamp()), 'title': sys.argv[1], 'date': sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else datetime.datetime.now().strftime('%Y-%m-%d'), 'time': sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else 'All Day'}); json.dump(data, open(f, 'w'), indent=2)",
            eventTitle,
            eventDate,
            eventTime
        ]
        onExited: syncCalendarProc.running = true
    }

    Process {
        id: deleteLocalEventProc
        property int eventId: 0
        command: ["python3", "-c", "import json, os; f=os.path.expanduser('~/.local/state/calendar_local.json'); data=[x for x in json.load(open(f)) if x.get('id') != " + eventId + "] if os.path.exists(f) else []; json.dump(data, open(f, 'w'), indent=2)"]
        onExited: syncCalendarProc.running = true
    }

    Process {
        id: readCalendarConfigProc
        command: ["python3", "-c", "import json, os; f=os.path.expanduser('~/.local/state/calendar_config.json'); print(json.load(open(f)).get('ics_url', '').strip()) if os.path.exists(f) else print('')"]
        stdout: SplitParser {
            onRead: data => {
                if (data !== undefined && data !== null) {
                    root.savedIcalUrl = data.trim()
                }
            }
        }
    }

    Process {
        id: saveCalendarConfigProc
        property string icsUrl: ""
        command: [
            "python3", "-c",
            "import json, os, sys; f=os.path.expanduser('~/.local/state/calendar_config.json'); os.makedirs(os.path.dirname(f), exist_ok=True); json.dump({'ics_url': sys.argv[1].strip()}, open(f, 'w'), indent=2)",
            icsUrl
        ]
        onExited: {
            root.savedIcalUrl = icsUrl.trim()
            syncCalendarProc.running = true
        }
    }

    function syncAgendaModel() {
        agendaModel.clear()
        for (var i = 0; i < allEvents.length; i++) {
            var ev = allEvents[i]
            var matches = true
            if (agendaFilter === "today" && !ev.isToday) matches = false
            if (agendaFilter === "upcoming" && ev.isToday) matches = false

            if (matches) {
                agendaModel.append({
                    "title": ev.title,
                    "dateDisplay": ev.dateDisplay || ev.date,
                    "time": ev.time || "All Day",
                    "location": ev.location || "",
                    "isToday": ev.isToday,
                    "source": ev.source,
                    "eventId": ev.id || 0
                })
            }
        }
    }

    function countEvents(filterKey) {
        var count = 0
        for (var i = 0; i < allEvents.length; i++) {
            if (filterKey === "today" && allEvents[i].isToday) count++
            else if (filterKey === "upcoming" && !allEvents[i].isToday) count++
            else if (filterKey === "all") count++
        }
        return count
    }

    ListModel { id: taskModel }
    ListModel { id: agendaModel }

    // Outer Shell Card
    Rectangle {
        id: mainCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(620, cardLayout.implicitHeight + 28)
        radius: 20
        color: root.colSurface
        border.color: root.colOutlineVariant
        border.width: 1
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
            }
        }

        ColumnLayout {
            id: cardLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            // ==========================================
            // Master Navigation: Sliding Pill Switcher
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 12
                color: root.colSurfaceLow

                // Animated sliding background pill
                Rectangle {
                    x: root.currentMainTab === "tasks" ? 3 : parent.width / 2 + 1
                    y: 3
                    width: parent.width / 2 - 4
                    height: parent.height - 6
                    radius: 9
                    color: root.currentMainTab === "tasks" ? root.colPrimary : root.colTertiary

                    Behavior on x {
                        NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Tasks Tab Pill
                    Rectangle {
                        color: "transparent"
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "task_alt"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 16
                                color: root.currentMainTab === "tasks" ? root.colTextOnPrimary : root.colTextVariant
                            }
                            Text {
                                text: "Tasks"
                                font.pixelSize: 13
                                font.bold: true
                                color: root.currentMainTab === "tasks" ? root.colTextOnPrimary : root.colTextVariant
                            }
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: root.currentMainTab === "tasks" ? root.colTextOnPrimary : root.colSurfaceHigh
                                Text {
                                    anchors.centerIn: parent
                                    text: String(root.countPending())
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.currentMainTab === "tasks" ? root.colPrimary : root.colTextVariant
                                }
                            }
                        }

                        TapHandler {
                            cursorShape: Qt.PointingHandCursor
                            onTapped: root.currentMainTab = "tasks"
                        }
                    }

                    // Agenda / Calendar Tab Pill
                    Rectangle {
                        color: "transparent"
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "calendar_month"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 16
                                color: root.currentMainTab === "agenda" ? "#2a1526" : root.colTextVariant
                            }
                            Text {
                                text: "Calendar"
                                font.pixelSize: 13
                                font.bold: true
                                color: root.currentMainTab === "agenda" ? "#2a1526" : root.colTextVariant
                            }
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: root.currentMainTab === "agenda" ? "#2a1526" : root.colSurfaceHigh
                                Text {
                                    anchors.centerIn: parent
                                    text: String(root.countEvents("all"))
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.currentMainTab === "agenda" ? root.colTertiary : root.colTextVariant
                                }
                            }
                        }

                        TapHandler {
                            cursorShape: Qt.PointingHandCursor
                            onTapped: {
                                root.currentMainTab = "agenda"
                                syncCalendarProc.running = true
                            }
                        }
                    }
                }
            }

            // ==========================================
            // Sliding Views Container
            // ==========================================
            Item {
                id: slidingContainer
                Layout.fillWidth: true
                implicitHeight: (root.currentMainTab === "tasks" ? tasksView.implicitHeight : agendaView.implicitHeight)
                clip: true

                // ------------------------------------------
                // View 1: Tasks (Today / Daily)
                // ------------------------------------------
                ColumnLayout {
                    id: tasksView
                    width: slidingContainer.width
                    spacing: 10
                    opacity: root.currentMainTab === "tasks" ? 1 : 0
                    visible: opacity > 0
                    x: root.currentMainTab === "tasks" ? 0 : -slidingContainer.width

                    Behavior on x {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    // Filter Icon Pills: All | Active | Done | Daily
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { "key": "all", "icon": "format_list_bulleted", "label": "All Tasks" },
                                { "key": "active", "icon": "radio_button_unchecked", "label": "Active Tasks" },
                                { "key": "done", "icon": "check_circle", "label": "Done Tasks" },
                                { "key": "daily", "icon": "autorenew", "label": "Daily Habits" }
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 28
                                radius: 8
                                color: root.activeFilter === modelData.key ? root.colSurfaceHighest : (filterHover.hovered ? root.colSurfaceHigh : "transparent")
                                border.color: root.activeFilter === modelData.key ? root.colPrimary : "transparent"
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                ToolTip.visible: filterHover.hovered
                                ToolTip.text: modelData.label
                                ToolTip.delay: 300

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 15
                                    color: root.activeFilter === modelData.key ? root.colPrimary : (filterHover.hovered ? root.colText : root.colOutline)
                                }

                                TapHandler {
                                    onTapped: {
                                        root.activeFilter = modelData.key
                                        root.syncTaskModel()
                                    }
                                }

                                HoverHandler {
                                    id: filterHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colOutlineVariant
                    }
                    // Super Cool Empty State
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 180
                        visible: taskModel.count === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                id: emptyIconTasks
                                text: "task_alt"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 56
                                color: root.colPrimary
                                Layout.alignment: Qt.AlignHCenter
                            }
                            
                            Text {
                                text: "You're all caught up!"
                                font.pixelSize: 15
                                font.bold: true
                                color: root.colText
                                Layout.alignment: Qt.AlignHCenter
                            }
                            
                            Text {
                                text: "Enjoy the peace, or add a new task below."
                                font.pixelSize: 12
                                color: root.colTextVariant
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }



                    // Task List View
                    ListView {
                        id: taskListView
                        Layout.fillWidth: true
                        implicitHeight: contentHeight
                        visible: taskModel.count > 0
                        clip: false
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 350; easing.type: Easing.OutExpo }
                                NumberAnimation { property: "x"; from: -20; to: 0; duration: 350; easing.type: Easing.OutExpo }
                            }
                        }
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: 250; easing.type: Easing.InCubic }
                                NumberAnimation { property: "scale"; to: 0.8; duration: 250; easing.type: Easing.InCubic }
                            }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 300; easing.type: Easing.OutExpo }
                        }

                        spacing: 6
                        interactive: false
                        model: taskModel

                        delegate: Item {
                            id: taskItemWrapper
                            width: taskListView.width
                            height: 42
                            clip: true

                            // Underneath: Red Slide-to-Delete background reveal
                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: root.colError
                                opacity: Math.min(1.0, Math.abs(taskCard.x) / 60)

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Text {
                                        text: "delete"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 18
                                        color: "#2a1526"
                                    }
                                    Text {
                                        text: taskCard.x < -80 ? "Release to delete" : "Slide to delete"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#2a1526"
                                    }
                                }
                            }

                            // Top: Draggable Task Card
                            Rectangle {
                                id: taskCard
                                width: parent.width
                                height: parent.height
                                radius: 9
                                color: taskHover.hovered ? root.colSurfaceHighest : (model.done ? root.colSurfaceLow : root.colSurfaceHigh)
                                border.color: taskHover.hovered ? root.colOutline : (model.done ? "transparent" : root.colOutlineVariant)
                                border.width: 1
                                scale: taskHover.hovered ? 1.008 : 1.0

                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                                DragHandler {
                                    id: dragHandler
                                    target: taskCard
                                    xAxis.maximum: 0
                                    xAxis.minimum: -taskItemWrapper.width
                                    yAxis.enabled: false

                                    onActiveChanged: {
                                        if (!active) {
                                            if (taskCard.x < -80) {
                                                deleteAnim.start()
                                            } else {
                                                snapAnim.start()
                                            }
                                        }
                                    }
                                }

                                NumberAnimation {
                                    id: snapAnim
                                    target: taskCard
                                    property: "x"
                                    to: 0
                                    duration: 320
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.1
                                }

                                SequentialAnimation {
                                    id: deleteAnim
                                    ParallelAnimation {
                                        NumberAnimation { target: taskCard; property: "x"; to: -taskItemWrapper.width; duration: 220; easing.type: Easing.InQuad }
                                        NumberAnimation { target: taskCard; property: "opacity"; to: 0; duration: 200 }
                                    }
                                    ScriptAction {
                                        script: root.deleteTask(model.rawIndex)
                                    }
                                }

                                HoverHandler { id: taskHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    // Animated Bouncy Checkbox
                                    Rectangle {
                                        id: checkBg
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 6
                                        color: model.done ? root.colSuccess : (checkHover.hovered ? root.colSurfaceHighest : "transparent")
                                        border.color: model.done ? root.colSuccess : (checkHover.hovered ? root.colTextVariant : root.colOutline)
                                        border.width: 1.5
                                        scale: model.done ? 1.0 : (checkHover.hovered ? 1.1 : 1.0)

                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                        Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: "#162319"
                                            opacity: model.done ? 1 : 0
                                            scale: model.done ? 1 : 0.5

                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        }

                                        TapHandler {
                                            onTapped: root.toggleTask(model.rawIndex)
                                        }
                                        HoverHandler {
                                            id: checkHover
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                    }

                                    // Daily recurring toggle badge
                                    Rectangle {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 4
                                        color: model.type === "daily" ? Qt.alpha(root.colTertiary, 0.2) : (habitHover.hovered ? root.colSurfaceHighest : "transparent")
                                        scale: habitHover.hovered ? 1.1 : 1.0

                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "↻"
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: model.type === "daily" ? root.colTertiary : root.colOutlineVariant
                                        }

                                        TapHandler {
                                            onTapped: root.toggleRecurring(model.rawIndex)
                                        }
                                        HoverHandler {
                                            id: habitHover
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                    }

                                    // Task Title
                                    Text {
                                        Layout.fillWidth: true
                                        text: model.text
                                        font.pixelSize: 13
                                        font.strikeout: model.done
                                        color: model.done ? root.colOutline : (titleHover.hovered ? root.colPrimary : root.colText)
                                        elide: Text.ElideRight

                                        Behavior on color { ColorAnimation { duration: 180 } }

                                        TapHandler {
                                            onTapped: root.toggleTask(model.rawIndex)
                                        }
                                        HoverHandler {
                                            id: titleHover
                                            cursorShape: Qt.PointingHandCursor
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: taskModel.count === 0
                        Layout.fillWidth: true
                        height: 32
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: root.activeFilter === "done" 
                                ? "No completed tasks yet" 
                                : (root.activeFilter === "active" ? "All done! ✦" : (root.activeFilter === "daily" ? "No daily habits added yet" : "No tasks added"))
                            font.pixelSize: 12
                            color: root.colOutline
                        }
                    }

                    // Task Input Field (Left recurring toggle + text input)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        implicitHeight: 36
                        spacing: 8

                        // Daily recurring toggle (Left Side)
                        Rectangle {
                            id: dailyToggleBtn
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 10
                            color: root.nextTaskIsDaily ? root.colTertiary : (repHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh)
                            border.color: root.nextTaskIsDaily ? root.colTertiary : (repHover.hovered ? root.colOutline : root.colOutlineVariant)
                            border.width: 1
                            scale: repTap.pressed ? 0.93 : (repHover.hovered ? 1.05 : 1.0)

                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                            ToolTip.visible: repHover.hovered
                            ToolTip.text: (root.nextTaskIsDaily ? "Creating Daily Habit" : "Make Daily Habit") + " (Ctrl+R)"
                            ToolTip.delay: 250

                            Text {
                                anchors.centerIn: parent
                                text: "autorenew"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 18
                                color: root.nextTaskIsDaily ? "#2a1526" : (repHover.hovered ? root.colText : root.colOutline)
                                rotation: root.nextTaskIsDaily ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                            }

                            TapHandler {
                                id: repTap
                                onTapped: {
                                    root.nextTaskIsDaily = !root.nextTaskIsDaily
                                    inputField.forceActiveFocus()
                                }
                            }
                            HoverHandler {
                                id: repHover
                                cursorShape: Qt.PointingHandCursor
                            }
                        }


                        TextField {
                            id: inputField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            implicitHeight: 36
                            placeholderText: root.nextTaskIsDaily ? "Add daily habit... (Press Enter)" : "Add task... (Press Enter)"
                            placeholderTextColor: Qt.alpha(root.colTextVariant, 0.7)
                            color: root.colText
                            font.pixelSize: 12
                            verticalAlignment: TextInput.AlignVCenter

                            background: Rectangle {
                                color: root.colSurfaceHigh
                                radius: 10
                                border.color: inputField.activeFocus ? (root.nextTaskIsDaily ? root.colTertiary : root.colPrimary) : root.colOutlineVariant
                                border.width: 1
                            }
                            padding: 10

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
                                    root.nextTaskIsDaily = !root.nextTaskIsDaily
                                    event.accepted = true
                                }
                            }

                            onAccepted: {
                                if (text.trim().length > 0) {
                                    root.addTask(text.trim(), root.nextTaskIsDaily ? "daily" : "today")
                                    text = ""
                                }
                            }
                        }
                    }
                }

                // ------------------------------------------
                // View 2: Agenda & Google Calendar
                // ------------------------------------------
                ColumnLayout {
                    id: agendaView
                    width: slidingContainer.width
                    spacing: 10
                    opacity: root.currentMainTab === "agenda" ? 1 : 0
                    visible: opacity > 0
                    x: root.currentMainTab === "agenda" ? 0 : slidingContainer.width

                    Behavior on x {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    // Filter row: Today | Upcoming | All + Sync Button (Icons)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { "key": "today", "icon": "today", "label": "Today's Events" },
                                { "key": "upcoming", "icon": "event_upcoming", "label": "Upcoming Events" },
                                { "key": "all", "icon": "calendar_month", "label": "All Events" }
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 28
                                radius: 8
                                color: root.agendaFilter === modelData.key ? root.colTertiary : (calFilterHover.hovered ? root.colSurfaceHigh : "transparent")
                                border.color: root.agendaFilter === modelData.key ? root.colTertiary : "transparent"
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                ToolTip.visible: calFilterHover.hovered
                                ToolTip.text: modelData.label
                                ToolTip.delay: 300

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 15
                                    color: root.agendaFilter === modelData.key ? "#2a1526" : (calFilterHover.hovered ? root.colText : root.colTextVariant)
                                }

                                TapHandler {
                                    onTapped: {
                                        root.agendaFilter = modelData.key
                                        root.syncAgendaModel()
                                    }
                                }

                                HoverHandler {
                                    id: calFilterHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }

                        // Sync button
                        Rectangle {
                            id: syncBtn
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 8
                            color: syncTap.pressed ? root.colSurfaceHighest : (syncHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh)
                            border.color: root.colOutlineVariant
                            border.width: 1
                            scale: syncTap.pressed ? 0.93 : (syncHover.hovered ? 1.05 : 1.0)

                            Behavior on scale { NumberAnimation { duration: 120 } }

                            ToolTip.visible: syncHover.hovered
                            ToolTip.text: "Sync Calendar"
                            ToolTip.delay: 250

                            Text {
                                anchors.centerIn: parent
                                text: "sync"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 16
                                color: root.colTertiary
                            }

                            TapHandler {
                                id: syncTap
                                onTapped: syncCalendarProc.running = true
                            }
                            HoverHandler {
                                id: syncHover
                                cursorShape: Qt.PointingHandCursor
                            }
                        }


                        // Connect Google Calendar Button
                        Rectangle {
                            id: connectCalBtn
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 8
                            color: root.calendarSettingsOpen ? root.colTertiary : (connHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh)
                            border.color: root.calendarSettingsOpen ? root.colTertiary : (root.savedIcalUrl.length > 0 ? root.colSuccess : root.colOutlineVariant)
                            border.width: 1
                            scale: connTap.pressed ? 0.93 : (connHover.hovered ? 1.05 : 1.0)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            ToolTip.visible: connHover.hovered
                            ToolTip.text: root.calendarSettingsOpen ? "Close Calendar Settings" : (root.savedIcalUrl.length > 0 ? "Google Calendar Connected (Click to edit)" : "Connect Google Calendar")
                            ToolTip.delay: 250

                            Text {
                                anchors.centerIn: parent
                                text: root.savedIcalUrl.length > 0 ? "cloud_done" : "cloud_sync"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 16
                                color: root.calendarSettingsOpen ? "#2a1526" : (root.savedIcalUrl.length > 0 ? root.colSuccess : root.colTertiary)
                            }

                            TapHandler {
                                id: connTap
                                onTapped: {
                                    root.calendarSettingsOpen = !root.calendarSettingsOpen
                                    if (root.calendarSettingsOpen) {
                                        icalUrlInput.text = root.savedIcalUrl
                                    }
                                }
                            }
                            HoverHandler {
                                id: connHover
                                cursorShape: Qt.PointingHandCursor
                            }
                        }

                    }

                    // Expandable Google Calendar Connect Drawer
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.calendarSettingsOpen ? (calSettingsCol.implicitHeight + 16) : 0
                        visible: Layout.preferredHeight > 0
                        opacity: root.calendarSettingsOpen ? 1.0 : 0.0
                        radius: 12
                        color: root.colSurfaceLow
                        border.color: root.savedIcalUrl.length > 0 ? root.colSuccess : root.colTertiary
                        border.width: 1
                        clip: true

                        Behavior on Layout.preferredHeight {
                            NumberAnimation {
                                duration: 320
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }

                        ColumnLayout {
                            id: calSettingsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.bottomMargin: 10
                            anchors.topMargin: root.calendarSettingsOpen ? 10 : -16
                            spacing: 8

                            Behavior on anchors.topMargin {
                                NumberAnimation {
                                    duration: 320
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                                }
                            }

                            // Header row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "calendar_month"
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 15
                                    color: root.colTertiary
                                }

                                Text {
                                    text: "Google Calendar Sync"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: root.colText
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    radius: 6
                                    color: root.savedIcalUrl.length > 0 ? Qt.alpha(root.colSuccess, 0.2) : Qt.alpha(root.colOutline, 0.2)
                                    implicitWidth: statusText.implicitWidth + 10
                                    implicitHeight: 18

                                    Text {
                                        id: statusText
                                        anchors.centerIn: parent
                                        text: root.savedIcalUrl.length > 0 ? "Connected" : "Not Linked"
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: root.savedIcalUrl.length > 0 ? root.colSuccess : root.colTextVariant
                                    }
                                }
                            }

                            // Instructions
                            Text {
                                Layout.fillWidth: true
                                text: "Paste Secret iCal URL (Google Calendar → Settings → Integrate calendar → Secret address in iCal format):"
                                font.pixelSize: 9
                                color: root.colTextVariant
                                wrapMode: Text.Wrap
                            }

                            // URL input field
                            TextField {
                                id: icalUrlInput
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                implicitHeight: 32
                                placeholderText: "https://calendar.google.com/calendar/ical/.../basic.ics"
                                placeholderTextColor: Qt.alpha(root.colTextVariant, 0.6)
                                color: root.colText
                                font.pixelSize: 11
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.savedIcalUrl

                                background: Rectangle {
                                    color: root.colSurfaceHigh
                                    radius: 8
                                    border.color: icalUrlInput.activeFocus ? root.colTertiary : root.colOutlineVariant
                                    border.width: 1
                                }
                                padding: 6

                                onAccepted: saveActionBtn.save()
                            }

                            // Action buttons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    id: saveActionBtn
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    implicitHeight: 28
                                    radius: 8
                                    color: root.colPrimary
                                    scale: saveActTap.pressed ? 0.95 : (saveActHover.hovered ? 1.02 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 120 } }

                                    function save() {
                                        if (icalUrlInput.text.trim().length > 0) {
                                            saveCalendarConfigProc.icsUrl = icalUrlInput.text.trim()
                                            saveCalendarConfigProc.running = true
                                            root.calendarSettingsOpen = false
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Connect & Sync"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.colTextOnPrimary
                                    }

                                    TapHandler {
                                        id: saveActTap
                                        onTapped: saveActionBtn.save()
                                    }
                                    HoverHandler {
                                        id: saveActHover
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }

                                // Remove / Disconnect button
                                Rectangle {
                                    visible: root.savedIcalUrl.length > 0
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    implicitHeight: 28
                                    radius: 8
                                    color: root.colSurfaceHigh
                                    border.color: discHover.hovered ? root.colError : root.colOutlineVariant
                                    border.width: 1

                                    ToolTip.visible: discHover.hovered
                                    ToolTip.text: "Disconnect Calendar"
                                    ToolTip.delay: 200

                                    Text {
                                        anchors.centerIn: parent
                                        text: "delete"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 15
                                        color: discHover.hovered ? root.colError : root.colTextVariant
                                    }

                                    TapHandler {
                                        id: discTap
                                        onTapped: {
                                            saveCalendarConfigProc.icsUrl = ""
                                            saveCalendarConfigProc.running = true
                                            icalUrlInput.text = ""
                                            root.calendarSettingsOpen = false
                                        }
                                    }
                                    HoverHandler {
                                        id: discHover
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colOutlineVariant
                    }

                    // Agenda Events List
                    ListView {
                        id: agendaListView
                        Layout.fillWidth: true
                        implicitHeight: contentHeight
                        clip: false
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 350; easing.type: Easing.OutExpo }
                                NumberAnimation { property: "x"; from: -20; to: 0; duration: 350; easing.type: Easing.OutExpo }
                            }
                        }
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: 250; easing.type: Easing.InCubic }
                                NumberAnimation { property: "scale"; to: 0.8; duration: 250; easing.type: Easing.InCubic }
                            }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 300; easing.type: Easing.OutExpo }
                        }

                        spacing: 6
                        interactive: false
                        model: agendaModel

                        delegate: Item {
                            id: eventItemWrapper
                            width: agendaListView.width
                            height: 48
                            clip: true

                            // Underneath: Red Slide-to-Delete reveal for local events
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: root.colError
                                visible: model.source === "local"
                                opacity: Math.min(1.0, Math.abs(eventCard.x) / 60)

                                RowLayout {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Text {
                                        text: "delete"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 18
                                        color: "#2a1526"
                                    }
                                    Text {
                                        text: eventCard.x < -80 ? "Release to delete" : "Slide to delete"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#2a1526"
                                    }
                                }
                            }

                            // Top: Event Card
                            Rectangle {
                                id: eventCard
                                width: parent.width
                                height: parent.height
                                radius: 10
                                color: eventHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh
                                border.color: model.isToday ? root.colTertiary : root.colOutlineVariant
                                border.width: 1
                                scale: eventHover.hovered ? 1.008 : 1.0

                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                                DragHandler {
                                    id: eventDragHandler
                                    enabled: model.source === "local"
                                    target: eventCard
                                    xAxis.maximum: 0
                                    xAxis.minimum: -eventItemWrapper.width
                                    yAxis.enabled: false

                                    onActiveChanged: {
                                        if (!active) {
                                            if (eventCard.x < -80) {
                                                deleteEventAnim.start()
                                            } else {
                                                snapEventAnim.start()
                                            }
                                        }
                                    }
                                }

                                NumberAnimation {
                                    id: snapEventAnim
                                    target: eventCard
                                    property: "x"
                                    to: 0
                                    duration: 320
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.1
                                }

                                SequentialAnimation {
                                    id: deleteEventAnim
                                    ParallelAnimation {
                                        NumberAnimation { target: eventCard; property: "x"; to: -eventItemWrapper.width; duration: 220; easing.type: Easing.InQuad }
                                        NumberAnimation { target: eventCard; property: "opacity"; to: 0; duration: 200 }
                                    }
                                    ScriptAction {
                                        script: {
                                            deleteLocalEventProc.eventId = model.eventId
                                            deleteLocalEventProc.running = true
                                        }
                                    }
                                }

                                HoverHandler { id: eventHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    // Time pill
                                    Rectangle {
                                        Layout.preferredWidth: 68
                                        Layout.preferredHeight: 28
                                        radius: 7
                                        color: model.isToday ? "#382334" : root.colSurfaceLow

                                        Text {
                                            anchors.centerIn: parent
                                            text: model.time
                                            font.pixelSize: 10
                                            font.bold: true
                                            color: model.isToday ? root.colTertiary : root.colTextVariant
                                        }
                                    }

                                    // Event Details
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: model.title
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: root.colText
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            spacing: 4
                                            Text {
                                                text: model.dateDisplay
                                                font.pixelSize: 10
                                                color: root.colOutline
                                            }
                                            Text {
                                                visible: model.location.length > 0
                                                text: "· " + model.location
                                                font.pixelSize: 10
                                                color: root.colPrimary
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty State for Agenda
                    Rectangle {
                        visible: agendaModel.count === 0
                        Layout.fillWidth: true
                        height: root.savedIcalUrl.length === 0 ? 56 : 40
                        color: "transparent"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "No events scheduled"
                                font.pixelSize: 12
                                color: root.colOutline
                            }
                            Text {
                                visible: root.savedIcalUrl.length > 0
                                Layout.alignment: Qt.AlignHCenter
                                text: "Add an event below"
                                font.pixelSize: 10
                                color: root.colTextVariant
                            }
                            Rectangle {
                                visible: root.savedIcalUrl.length === 0 && !root.calendarSettingsOpen
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: emptyConnText.implicitWidth + 16
                                implicitHeight: 22
                                radius: 6
                                color: emptyConnHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh
                                border.color: root.colTertiary
                                border.width: 1

                                Text {
                                    id: emptyConnText
                                    anchors.centerIn: parent
                                    text: "＋ Connect Google Calendar"
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.colTertiary
                                }

                                TapHandler {
                                    onTapped: {
                                        root.calendarSettingsOpen = true
                                        icalUrlInput.forceActiveFocus()
                                    }
                                }
                                HoverHandler {
                                    id: emptyConnHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }
                    }

                    // Quick Add Event Field (Press Enter to Add!)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            spacing: 8

                            function triggerAddEvent() {
                                if (eventTitleInput.text.trim().length > 0) {
                                    addLocalEventProc.eventTitle = eventTitleInput.text.trim()
                                    addLocalEventProc.eventDate = root.selectedEventDate || root.getTodayString()
                                    addLocalEventProc.eventTime = root.selectedEventTime || "All Day"
                                    addLocalEventProc.running = true
                                    eventTitleInput.text = ""
                                    root.selectedEventDate = root.getTodayString()
                                    root.selectedEventDateLabel = "Today"
                                    root.selectedEventTime = "All Day"
                                    root.dateTimeSelectorOpen = false
                                }
                            }

                            TextField {
                                id: eventTitleInput
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                placeholderText: "Event title... (Press Enter)"
                                placeholderTextColor: Qt.alpha(root.colTextVariant, 0.7)
                                color: root.colText
                                font.pixelSize: 12
                                verticalAlignment: TextInput.AlignVCenter

                                background: Rectangle {
                                    color: root.colSurfaceHigh
                                    radius: 10
                                    border.color: eventTitleInput.activeFocus ? root.colTertiary : root.colOutlineVariant
                                    border.width: 1
                                }
                                padding: 10

                                onAccepted: parent.triggerAddEvent()
                            }

                            // Date & Time Selector Trigger Button
                            Rectangle {
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 36
                                radius: 10
                                color: root.dateTimeSelectorOpen ? root.colSurfaceHighest : root.colSurfaceHigh
                                border.color: root.dateTimeSelectorOpen ? root.colTertiary : root.colOutlineVariant
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: "event"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 15
                                        color: root.dateTimeSelectorOpen ? root.colTertiary : root.colTextVariant
                                    }

                                    Text {
                                        text: root.selectedEventDateLabel + " · " + (root.selectedEventTime === "All Day" ? "All Day" : root.selectedEventTime.replace(":00", ""))
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: root.dateTimeSelectorOpen ? root.colTertiary : root.colText
                                        elide: Text.ElideRight
                                    }
                                }

                                TapHandler {
                                    onTapped: root.dateTimeSelectorOpen = !root.dateTimeSelectorOpen
                                }
                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }
                        }

                        // Expandable Date & Time selector drawer
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.dateTimeSelectorOpen ? (dtSelectorCol.implicitHeight + 16) : 0
                            visible: Layout.preferredHeight > 0
                            opacity: root.dateTimeSelectorOpen ? 1.0 : 0.0
                            radius: 12
                            color: root.colSurfaceLow
                            border.color: root.colOutlineVariant
                            border.width: 1
                            clip: true

                            Behavior on Layout.preferredHeight {
                                NumberAnimation {
                                    duration: 320
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }

                            ColumnLayout {
                                id: dtSelectorCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.bottomMargin: 8
                                anchors.topMargin: root.dateTimeSelectorOpen ? 8 : -16
                                spacing: 8

                                Behavior on anchors.topMargin {
                                    NumberAnimation {
                                        duration: 320
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                                    }
                                }

                                // --- Date Header ---
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: "calendar_today"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 13
                                        color: root.colTertiary
                                    }
                                    Text {
                                        text: "Date:"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.colTextVariant
                                    }
                                    Text {
                                        text: root.selectedEventDateLabel
                                        font.pixelSize: 11
                                        color: root.colTertiary
                                        font.bold: true
                                    }
                                }

                                // Date Chips: 8 upcoming days
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 4
                                    columnSpacing: 5
                                    rowSpacing: 5

                                    Repeater {
                                        model: root.getUpcomingDays()
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 26
                                            radius: 7
                                            color: root.selectedEventDate === modelData.iso ? root.colTertiary : (dateChipHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh)
                                            border.color: root.selectedEventDate === modelData.iso ? root.colTertiary : (dateChipHover.hovered ? root.colTextVariant : root.colOutlineVariant)
                                            border.width: 1
                                            scale: dateChipHover.hovered ? 1.05 : 1.0

                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: 10
                                                color: root.selectedEventDate === modelData.iso ? "#2a1526" : root.colText
                                                font.bold: root.selectedEventDate === modelData.iso
                                            }

                                            TapHandler {
                                                onTapped: {
                                                    root.selectedEventDate = modelData.iso
                                                    root.selectedEventDateLabel = modelData.label
                                                }
                                            }
                                            HoverHandler {
                                                id: dateChipHover
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: root.colOutlineVariant
                                }

                                // --- Time Header ---
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: "schedule"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 13
                                        color: root.colTertiary
                                    }
                                    Text {
                                        text: "Time:"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: root.colTextVariant
                                    }
                                    Text {
                                        text: root.selectedEventTime
                                        font.pixelSize: 11
                                        color: root.colTertiary
                                        font.bold: true
                                    }
                                }

                                // Time Chips
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 3
                                    columnSpacing: 5
                                    rowSpacing: 5

                                    Repeater {
                                        model: ["All Day", "09:00 AM", "12:00 PM", "03:00 PM", "06:00 PM", "08:00 PM"]
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 26
                                            radius: 7
                                            color: root.selectedEventTime === modelData ? root.colTertiary : (timeChipHover.hovered ? root.colSurfaceHighest : root.colSurfaceHigh)
                                            border.color: root.selectedEventTime === modelData ? root.colTertiary : (timeChipHover.hovered ? root.colTextVariant : root.colOutlineVariant)
                                            border.width: 1
                                            scale: timeChipHover.hovered ? 1.05 : 1.0

                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.pixelSize: 10
                                                color: root.selectedEventTime === modelData ? "#2a1526" : root.colText
                                                font.bold: root.selectedEventTime === modelData
                                            }

                                            TapHandler {
                                                onTapped: {
                                                    root.selectedEventTime = modelData
                                                }
                                            }
                                            HoverHandler {
                                                id: timeChipHover
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
