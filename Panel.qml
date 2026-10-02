import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var service: null
  property bool opened: false
  readonly property color foreground: Color.foreground
  readonly property string fontFamily: Style.font.family
  readonly property color mutedColor: Qt.darker(foreground, 1.4)
  readonly property bool controllable: service !== null && service.connected && !service.busy
  readonly property var antiWindModes: ["off", "auto", "max"]
  readonly property var panelBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: Color.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
  }

  readonly property var rows: [
    toggleRow("anc", "anc", "Active noise cancellation", "Reduce surrounding noise", "Noise control"),
    toggleRow("adaptive", "adaptive", "Adaptive noise control", "Adjust cancellation to the surroundings", "Noise control"),
    { key: "transparency", kind: "slider", primaryText: "Transparency", secondaryText: "Hear your surroundings", section: "Noise control" },
    toggleRow("smart-pause", "smartPause", "Smart Pause", "Pause playback when the headphones are removed", "Behaviour"),
    toggleRow("on-head-detection", "onHeadDetection", "On-head detection", "Detect when the headphones are being worn", "Behaviour"),
    toggleRow("auto-answer", "autoAnswer", "Auto-answer", "Answer calls when the headphones are put on", "Behaviour"),
    toggleRow("comfort-call", "comfortCall", "Comfort Call", "Adjust call audio for comfort", "Behaviour"),
    { key: "anti-wind", kind: "choice", primaryText: "Anti-wind", secondaryText: "Off auto max", section: "Anti-wind" }
  ]

  function toggleRow(key, property, label, description, section) {
    return { key: key, kind: "toggle", property: property, primaryText: label, secondaryText: description, section: section }
  }

  function hasCursor(key) {
    return filterController.cursorActive && filterController.cursorIndex === filterController.indexForKey(key)
  }

  function sectionVisible(section) {
    return filterController.filteredModel.some(function(entry) { return entry.section === section })
  }

  function rowVisible(key) {
    return filterController.indexForKey(key) >= 0
  }

  function setCursor(key) {
    filterController.selectIndex(filterController.indexForKey(key))
  }

  function toggle(entry) {
    if (!controllable) return
    service.setValue(entry.key, service[entry.property] ? "off" : "on")
  }

  function stepAntiWind(delta) {
    if (!controllable) return
    var index = antiWindModes.indexOf(service.antiWind)
    var next = Math.max(0, Math.min(antiWindModes.length - 1, index + delta))
    if (next !== index) service.setValue("anti-wind", antiWindModes[next])
  }

  function stepTransparency(delta) {
    if (!controllable) return
    var current = transparencyDebounce.running ? transparencyDebounce.value : service.transparency
    var next = Math.max(0, Math.min(100, current + delta))
    if (next === current) return
    transparencySlider.liveValue = next
    transparencyDebounce.value = next
    transparencyDebounce.restart()
  }

  function activate(entry) {
    if (!entry) return
    if (entry.kind === "toggle") toggle(entry)
    else if (entry.kind === "choice" && controllable)
      service.setValue("anti-wind", antiWindModes[(antiWindModes.indexOf(service.antiWind) + 1) % antiWindModes.length])
  }

  function adjust(direction) {
    var entry = filterController.selectedEntry()
    if (!entry) return false
    if (entry.kind === "slider") stepTransparency(direction * transparencySlider.step)
    else if (entry.kind === "choice") stepAntiWind(direction)
    else return false
    return true
  }

  function heroMeta() {
    if (!service) return "Waiting for headset"
    if (service.connected) return "Connected · Battery " + service.battery + "%"
    return service.error ? service.error : "Waiting for headset"
  }

  function scrollCursorIntoView() {
    var entry = filterController.selectedEntry()
    var item = entry ? rowItems[entry.key] : null
    if (!item || !item.visible) return
    var point = item.mapToItem(contentColumn, 0, 0)
    if (point.y < scrollArea.contentY) scrollArea.contentY = point.y
    else if (point.y + item.height > scrollArea.contentY + scrollArea.height)
      scrollArea.contentY = point.y + item.height - scrollArea.height
  }

  readonly property var rowItems: ({
    "anc": ancRow,
    "adaptive": adaptiveRow,
    "transparency": transparencyRow,
    "smart-pause": smartPauseRow,
    "on-head-detection": onHeadRow,
    "auto-answer": autoAnswerRow,
    "comfort-call": comfortCallRow,
    "anti-wind": antiWindRow
  })

  function open(payloadJson) {
    opened = true
    filterController.reset()
    if (service) service.refresh()
    Qt.callLater(function() {
      scrollArea.contentY = 0
      filterController.forceActiveFocus()
    })
  }
  function close() {
    opened = false
  }
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("timmo.momentumctl")
    else close()
  }

  component ToggleRow: Toggle {
    id: toggleRow
    required property var panel
    required property string rowKey
    readonly property var entry: panel.rows.find(function(row) { return row.key === rowKey })
    visible: panel.rowVisible(rowKey)
    width: parent.width
    label: entry.primaryText
    description: entry.secondaryText
    foreground: panel.foreground
    fontFamily: panel.fontFamily
    checked: panel.service ? panel.service[entry.property] : false
    enabled: panel.controllable
    hasCursor: panel.hasCursor(rowKey)
    onHovered: function(isHovered) { if (isHovered) panel.setCursor(toggleRow.rowKey) }
    onClicked: {
      panel.setCursor(rowKey)
      panel.toggle(entry)
    }
  }

  component SectionHeader: PanelSectionHeader {
    required property var panel
    foreground: panel.foreground
    fontFamily: panel.fontFamily
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "timmo-momentumctl"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea {
        anchors.fill: parent
        onClicked: root.requestClose()
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(Style.space(430), parent.width - Style.space(32))
      height: Math.min(contentColumn.implicitHeight + Style.space(32), parent.height - Style.space(32))
      color: Color.background
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      // FilterablePanel leaves Left and Right unhandled, so they reach this
      // item and adjust the slider or anti-wind row under the cursor.
      Item {
        anchors.fill: parent
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Left || event.key === Qt.Key_Right)
            event.accepted = root.adjust(event.key === Qt.Key_Left ? -1 : 1)
        }

        FilterablePanel {
          id: filterController
          anchors.fill: parent
          model: root.rows
          onActivateRequested: function(entry) { root.activate(entry) }
          onCloseRequested: root.requestClose()
          onRefreshRequested: if (root.service) root.service.refresh()
          onRevealRequested: Qt.callLater(root.scrollCursorIntoView)

          PanelFlickable {
            id: scrollArea
            anchors.fill: parent
            anchors.margins: Style.space(16)
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: contentColumn
              width: scrollArea.width
              spacing: Style.space(12)

              PanelHeader {
                title: "momentumctl"
                meta: root.heroMeta()
                detail: root.service && root.service.connected ? "HEADPHONES" : "OFFLINE"
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconOpacity: root.service && root.service.connected ? 1 : 0.5
                iconComponent: Component {
                  Text {
                    text: "󰋋"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                  }
                }
              }

              Text {
                visible: filterController.filterText !== ""
                width: parent.width
                text: filterController.count > 0
                  ? "Filter: " + filterController.filterText
                  : "No matches for “" + filterController.filterText + "”"
                textFormat: Text.PlainText
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              PanelSeparator { visible: root.sectionVisible("Noise control"); foreground: root.foreground }
              SectionHeader { panel: root; visible: root.sectionVisible("Noise control"); text: "NOISE CONTROL" }

              ToggleRow { id: ancRow; panel: root; rowKey: "anc" }
              ToggleRow { id: adaptiveRow; panel: root; rowKey: "adaptive" }

              CursorSurface {
                id: transparencyRow
                visible: root.rowVisible("transparency")
                width: parent.width
                implicitHeight: transparencyColumn.implicitHeight + Style.spacing.huge
                hasCursor: root.hasCursor("transparency")
                foreground: root.foreground
                bordered: true

                HoverHandler {
                  onHoveredChanged: if (hovered) root.setCursor("transparency")
                }

                Column {
                  id: transparencyColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  spacing: Style.space(6)

                  Item {
                    width: parent.width
                    implicitHeight: Math.max(transparencyLabel.implicitHeight, transparencyValue.implicitHeight)
                    Text {
                      id: transparencyLabel
                      text: "Transparency"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle
                      font.bold: true
                      anchors.left: parent.left
                    }
                    Text {
                      id: transparencyValue
                      text: Math.round(transparencySlider.liveValue) + "%"
                      color: root.mutedColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.right: parent.right
                      anchors.verticalCenter: transparencyLabel.verticalCenter
                    }
                  }

                  PanelSlider {
                    id: transparencySlider
                    bar: root.panelBar
                    width: parent.width
                    minimum: 0
                    maximum: 100
                    step: 5
                    value: root.service ? root.service.transparency : 0
                    enabled: root.controllable
                    opacity: enabled ? 1 : 0.5
                    onMoved: function(value) {
                      root.setCursor("transparency")
                      transparencyDebounce.value = Math.round(value)
                      transparencyDebounce.restart()
                    }
                  }
                }
              }

              PanelSeparator { visible: root.sectionVisible("Behaviour"); foreground: root.foreground }
              SectionHeader { panel: root; visible: root.sectionVisible("Behaviour"); text: "BEHAVIOUR" }

              ToggleRow { id: smartPauseRow; panel: root; rowKey: "smart-pause" }
              ToggleRow { id: onHeadRow; panel: root; rowKey: "on-head-detection" }
              ToggleRow { id: autoAnswerRow; panel: root; rowKey: "auto-answer" }
              ToggleRow { id: comfortCallRow; panel: root; rowKey: "comfort-call" }

              PanelSeparator { visible: root.sectionVisible("Anti-wind"); foreground: root.foreground }
              SectionHeader { panel: root; visible: root.sectionVisible("Anti-wind"); text: "ANTI-WIND" }

              ButtonGroup {
                id: antiWindRow
                visible: root.rowVisible("anti-wind")
                width: parent.width
                focusable: false
                enabled: root.controllable
                opacity: enabled ? 1 : 0.5
                options: root.antiWindModes.map(function(mode) {
                  return { value: mode, label: mode.toUpperCase() }
                })
                value: root.service ? root.service.antiWind : "off"
                cursorIndex: root.hasCursor("anti-wind") ? root.antiWindModes.indexOf(value) : -1
                foreground: root.foreground
                fontFamily: root.fontFamily
                onHovered: function(index, isHovered) { if (isHovered) root.setCursor("anti-wind") }
                onChanged: function(mode) {
                  root.setCursor("anti-wind")
                  if (root.controllable) root.service.setValue("anti-wind", mode)
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: transparencyDebounce
    property int value: 0
    interval: 350
    repeat: false
    onTriggered: if (root.service) root.service.setValue("transparency", value)
  }
}
