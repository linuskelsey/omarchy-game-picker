import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "GameSearch.js" as GameSearch

// Fullscreen searchable game launcher. Scans wine/rom/Steam libraries on
// each open via bin/scan.sh and launches the pick via Quickshell.execDetached
// with a plain argv array — no shell string is ever built, so names/paths
// with spaces or apostrophes need no escaping anywhere in here.
Item {
  id: root

  // Host never injects a plugin-dir path (confirmed against shell.qml — only
  // shell/manifest get set on plugin instances), so hardcode it like the
  // football-tracker plugin does.
  property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/prometheus.game-picker"
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var games: []
  property var filteredGames: []

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.accent
  // Force the accent color rather than Border.surfaceSpec("menu", "border", ...),
  // which looks up the theme's own [menu] border token first and only falls
  // back to our color when the theme leaves it unset — this theme sets one,
  // so the fallback color was always being silently ignored.
  property var borderSpec: Border.flat(border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowHeight: Style.space(56)

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    scanProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "prometheus.game-picker")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadGames(raw) {
    root.games = GameSearch.parseGames(raw)
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var out = GameSearch.filterGames(root.games, root.filterText)
    root.filteredGames = out

    displayModel.clear()
    for (var j = 0; j < out.length; j++) {
      var g = out[j]
      displayModel.append({
        gameName: g.name || "",
        platform: g.platform || "",
        icon: g.icon || "",
        launchType: (g.launch && g.launch.type) || "",
        launchJson: JSON.stringify(g.launch || {})
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function move(delta) {
    if (displayModel.count === 0) return
    selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  // Jump by roughly one screenful, clamped (no wrap, unlike move()).
  function page(direction) {
    if (displayModel.count === 0) return
    var step = Math.max(1, Math.floor(resultList.height / (root.rowHeight + Style.space(4))) - 1)
    selectedIndex = Math.max(0, Math.min(displayModel.count - 1, selectedIndex + direction * step))
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    var launch
    try { launch = JSON.parse(row.launchJson) } catch (e) { launch = null }
    if (!launch) return
    root.dismiss()
    root.launchGame(launch)
  }

  function launchGame(launch) {
    switch (launch.type) {
      case "wine":
        Quickshell.execDetached([root.pluginDir + "/bin/launch-wine.sh", launch.dir, launch.exe])
        break
      case "native":
        Quickshell.execDetached([root.pluginDir + "/bin/launch-native.sh", launch.dir, launch.binary])
        break
      case "retroarch":
        Quickshell.execDetached(["retroarch", "-L", launch.core, launch.rom])
        break
      case "steam":
        Quickshell.execDetached(["steam", "-applaunch", launch.appid])
        break
      case "desktop":
        Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", launch.id + ".desktop"])
        break
    }
  }

  // Gamepad control (driven by the dualsense-ps-menu daemon). Separate target
  // from the host's "shell" one so the daemon can open/navigate/launch without
  // synthesising keyboard events.
  IpcHandler {
    target: "game-picker"
    function open(): string { if (!root.opened) root.open("{}"); return "ok" }
    function close(): string { if (root.opened) root.dismiss(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function move(delta: string): string { root.move(parseInt(delta) || 0); return "ok" }
    function page(direction: string): string { root.page(parseInt(direction) || 0); return "ok" }
    function activate(): string { root.activateIndex(root.selectedIndex); return "ok" }
    function isOpen(): string { return root.opened ? "open" : "closed" }
  }

  ListModel { id: displayModel }

  Process {
    id: scanProc
    command: [root.pluginDir + "/bin/scan.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadGames(text)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "prometheus-game-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterText.length > 0) root.setFilter(root.filterText.slice(0, -1))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.move(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.move(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search games…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property int index
              required property string gameName
              required property string platform
              required property string icon

              readonly property bool hasCursor: index === root.selectedIndex

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(12)

                Item {
                  id: iconFrame
                  width: Style.space(36)
                  height: Style.space(36)
                  anchors.verticalCenter: parent.verticalCenter

                  Rectangle {
                    id: iconMask
                    anchors.fill: parent
                    radius: Style.space(6)
                    color: "white"
                    visible: false
                    layer.enabled: true
                  }

                  Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                      maskEnabled: true
                      maskSource: iconMask
                    }

                    Image {
                      anchors.fill: parent
                      visible: row.icon !== ""
                      source: row.icon !== "" ? Qt.resolvedUrl("file://" + row.icon) : ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                    }

                    Rectangle {
                      anchors.fill: parent
                      visible: row.icon === ""
                      color: Qt.darker(root.background, 1.3)

                      Text {
                        anchors.centerIn: parent
                        text: GameSearch.platformGlyph(row.platform)
                        color: row.hasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                      }
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(6)
                    color: "transparent"
                    border.width: Math.max(1, Style.space(1))
                    border.color: Color.accent
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  width: parent.width - Style.space(48)

                  Text {
                    textFormat: Text.PlainText
                    text: row.gameName
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    width: parent.width
                    elide: Text.ElideRight
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: row.platform
                    color: row.hasCursor ? root.selectedText : Qt.darker(root.foreground, 1.4)
                    opacity: 0.8
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = row.index
                onClicked: root.activateIndex(row.index)
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              textFormat: Text.PlainText
              text: root.games.length === 0 ? "Scanning your library…" : "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }
      }
    }
  }
}
