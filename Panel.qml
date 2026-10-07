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
  readonly property color mutedColor: Qt.darker(foreground, 1.35)
  readonly property bool connected: service !== null && service.connected
  readonly property bool controllable: connected && !service.busy
  readonly property var antiWindModes: ["off", "auto", "max"]
  readonly property var autoPowerOffChoices: ["never", "15", "30", "60"]
  readonly property var eqPresets: ["neutral", "rock", "pop", "dance", "hip-hop", "classical", "movie", "jazz", "harman"]
  readonly property var transparencyModes: ["off", "adaptive", "custom"]
  readonly property string transparencyMode: connected ? service.transparencyMode : ""
  readonly property int transparencyStep: 10
  // Shared live value so the custom button, slider, and keyboard steps agree
  // while a transparency change is still waiting to be sent.
  property int transparencyLive: 0
  // Band gains as shown, ahead of the headset while a change waits to be sent.
  property var eqLive: []
  readonly property var eqBandLabels: ["63 Hz", "250 Hz", "1 kHz", "4 kHz", "8 kHz"]
  readonly property real eqGainStep: 0.5
  readonly property real eqGainLimit: 12
  readonly property string cursorKey: filterController.selectedEntry() ? filterController.selectedEntry().key : ""
  readonly property string cursorRowKey: filterController.selectedEntry() ? filterController.selectedEntry().rowKey : ""
  readonly property var panelBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: Color.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
  }

  // Transparency covers the whole noise control state: off, adaptive, or a
  // custom level. Anti-wind has nothing to act on with noise control off.
  readonly property var rows: [
    { key: "transparency", kind: "transparency", choices: transparencyModes, property: "transparencyMode", icon: 0xf07c5, primaryText: "Transparency", secondaryText: "off adaptive custom noise", section: "Noise control" }
  ].concat(transparencyMode !== "off" ? [
    { key: "anti-wind", kind: "choice", choices: antiWindModes, property: "antiWind", icon: 0xf059d, primaryText: "Anti-wind", secondaryText: "off auto max", section: "Noise control" }
  ] : []).concat(service && service.bassBoost !== null ? [
    toggleRow("bass-boost", "bassBoost", 0xf0f6f, "Bass boost", "Sound")
  ] : []).concat(service && service.eqPreset !== null ? [
    { key: "eq-preset", kind: "preset", choices: eqPresets, property: "eqPreset", icon: 0xf0ea2, primaryText: "Equaliser", secondaryText: "eq preset " + eqPresets.join(" "), section: "Sound" }
  ] : []).concat([
    toggleRow("smart-pause", "smartPause", 0xf03e6, "Smart Pause", "Behaviour"),
    toggleRow("on-head-detection", "onHeadDetection", 0xf133b, "On-head detection", "Behaviour"),
    toggleRow("auto-answer", "autoAnswer", 0xf03f6, "Auto-answer", "Behaviour"),
    toggleRow("comfort-call", "comfortCall", 0xf05cb, "Comfort Call", "Behaviour")
  ]).concat(service && service.touchControls !== null ? [
    toggleRow("touch-controls", "touchControls", 0xf0741, "Touch controls", "Behaviour")
  ] : []).concat(service && service.autoPowerOff !== null ? [
    { key: "auto-power-off", kind: "choice", choices: autoPowerOffChoices, property: "autoPowerOff", icon: 0xf0904, primaryText: "Auto power off", secondaryText: "never 15 30 60 minutes", section: "Behaviour" }
  ] : [])

  function toggleRow(key, property, icon, label, section) {
    return { key: key, kind: "toggle", property: property, icon: icon, primaryText: label, secondaryText: "", section: section }
  }

  // Every clickable control is its own cursor stop, so Up and Down walk the
  // buttons inside a row as well as the rows themselves.
  function buildNavigationEntries(entries) {
    var targets = [{ key: "action:refresh", rowKey: "action:refresh", kind: "refresh", navigation: true }]
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (entry.kind === "toggle")
        targets.push({ key: entry.key, rowKey: entry.key, row: entry, kind: "toggle" })
      else if (entry.kind === "preset") {
        targets.push({ key: entry.key + ":previous", rowKey: entry.key, row: entry, kind: "cycle", delta: -1 })
        targets.push({ key: entry.key + ":next", rowKey: entry.key, row: entry, kind: "cycle", delta: 1 })
        for (var band = 0; band < eqBandLabels.length; band++)
          targets.push({ key: "eq-band:" + band, rowKey: entry.key, row: entry, kind: "band", band: band })
      }
      else if (entry.kind === "choice" || entry.kind === "transparency") {
        for (var choice = 0; choice < entry.choices.length; choice++)
          targets.push({ key: entry.key + ":" + entry.choices[choice], rowKey: entry.key, row: entry, kind: "choice", value: entry.choices[choice] })
        if (entry.kind === "transparency" && transparencyMode === "custom") {
          targets.push({ key: entry.key + ":decrement", rowKey: entry.key, row: entry, kind: "step", delta: -1 })
          targets.push({ key: entry.key + ":increment", rowKey: entry.key, row: entry, kind: "step", delta: 1 })
        }
      }
    }
    return targets
  }

  function sectionRows(section) {
    return filterController.filteredModel.filter(function(entry) { return entry.section === section })
  }

  function select(key) {
    filterController.selectIndex(filterController.indexForKey(key))
  }

  function targetSelected(key) {
    return cursorKey === key
  }

  function onOff(value) {
    return value ? "On" : "Off"
  }

  function choiceLabel(value) {
    if (/^\d+$/.test(value)) return value + " min"
    return value.split("-").map(function(part) { return part.charAt(0).toUpperCase() + part.slice(1) }).join("-")
  }

  function eqGainLabel(gain) {
    return (gain > 0 ? "+" : "") + gain + " dB"
  }

  function rowValue(entry) {
    if (!connected) return "Unavailable"
    if (entry.kind === "toggle") return onOff(service[entry.property])
    if (entry.kind === "preset") return "Stored on the headset"
    if (entry.kind === "transparency") {
      if (transparencyMode === "adaptive") return "Adaptive, " + service.transparency + "%"
      if (transparencyMode === "custom") return Math.round(transparencyLive) + "%"
    }
    return choiceLabel(service[entry.property])
  }

  function rowActive(entry) {
    if (!connected) return false
    if (entry.kind === "toggle") return service[entry.property]
    if (entry.kind === "preset") return service.eqPreset !== "neutral"
    return service[entry.property] !== "off" && service[entry.property] !== "never"
  }

  function toggle(entry) {
    if (controllable) service.setValue(entry.key, service[entry.property] ? "off" : "on")
  }

  function setChoice(entry, value) {
    if (!controllable || service[entry.property] === value) return
    if (entry.kind === "transparency") service.setTransparencyMode(value)
    else service.setValue(entry.key, value)
  }

  function stepChoice(entry, delta) {
    if (!controllable) return
    var index = entry.choices.indexOf(service[entry.property])
    setChoice(entry, entry.choices[Math.max(0, Math.min(entry.choices.length - 1, index + delta))])
  }

  // Presets wrap around. A custom curve starts from the first or last one.
  function cyclePreset(entry, delta) {
    if (!controllable) return
    var index = entry.choices.indexOf(service[entry.property])
    var next = index < 0 ? (delta > 0 ? 0 : entry.choices.length - 1)
      : (index + delta + entry.choices.length) % entry.choices.length
    service.setValue(entry.key, entry.choices[next])
  }

  function setEqBand(band, gain) {
    if (!controllable || band >= eqLive.length) return
    var snapped = Math.round(Math.max(-eqGainLimit, Math.min(eqGainLimit, gain)) / eqGainStep) * eqGainStep
    if (snapped === eqLive[band]) return
    var next = eqLive.slice()
    next[band] = snapped
    eqLive = next
    eqDebounce.restart()
  }

  function stepEqBand(band, delta) {
    if (band < eqLive.length) setEqBand(band, eqLive[band] + delta * eqGainStep)
  }

  // Sends only the bands that differ from the headset, once it's free.
  function sendEq() {
    if (!service || !service.eq) return
    if (service.busy) {
      eqDebounce.restart()
      return
    }
    var commands = []
    for (var band = 0; band < eqLive.length; band++)
      if (eqLive[band] !== service.eq[band]) commands.push(["eq-band", band, eqLive[band]])
    service.setValues(commands)
  }

  function stepTransparency(delta) {
    if (!controllable || transparencyMode !== "custom") return
    var current = transparencyDebounce.running ? transparencyDebounce.value : transparencyLive
    var next = Math.max(0, Math.min(100, current + delta * transparencyStep))
    if (next === current) return
    setTransparency(next)
  }

  function setTransparency(value) {
    transparencyLive = value
    transparencyDebounce.value = value
    transparencyDebounce.restart()
  }

  function activateEntry(entry) {
    if (!entry) return
    if (entry.kind === "refresh") { if (service) service.refresh() }
    else if (entry.kind === "toggle") toggle(entry.row)
    else if (entry.kind === "step") stepTransparency(entry.delta)
    else if (entry.kind === "choice") setChoice(entry.row, entry.value)
    else if (entry.kind === "cycle") cyclePreset(entry.row, entry.delta)
    else if (entry.kind === "band") setEqBand(entry.band, 0)
  }

  function adjust(direction) {
    var entry = filterController.selectedEntry()
    if (!entry || !entry.row) return false
    if (entry.kind === "step") stepTransparency(direction)
    else if (entry.kind === "choice") stepChoice(entry.row, direction)
    else if (entry.kind === "cycle") cyclePreset(entry.row, direction)
    else if (entry.kind === "band") stepEqBand(entry.band, direction)
    else return false
    return true
  }

  function batteryIcon(level) {
    if (level >= 95) return String.fromCodePoint(0xf0079)
    return String.fromCodePoint(0xf007a + Math.max(0, Math.min(8, Math.floor(level / 10) - 1)))
  }

  function heroMeta() {
    if (connected) return service.firmware ? "Firmware " + service.firmware : ""
    if (service && service.error) return service.error
    return "Waiting for headset"
  }

  function scrollCursorIntoView() {
    var item = null
    if (cursorRowKey === "action:refresh") item = noiseHeading
    else {
      var repeaters = [noiseRepeater, soundRepeater, behaviourRepeater]
      for (var r = 0; r < repeaters.length && !item; r++)
        for (var i = 0; i < repeaters[r].count; i++)
          if (repeaters[r].itemAt(i) && repeaters[r].itemAt(i).rowKey === cursorRowKey) item = repeaters[r].itemAt(i)
    }
    if (!item) return
    var point = item.mapToItem(contentColumn, 0, 0)
    if (point.y < scrollArea.contentY) scrollArea.contentY = point.y
    else if (point.y + item.height > scrollArea.contentY + scrollArea.height)
      scrollArea.contentY = point.y + item.height - scrollArea.height
  }

  function open(payloadJson) {
    opened = true
    filterController.reset()
    if (service) {
      transparencyLive = service.customTransparency
      eqLive = service.eq ? service.eq.slice() : []
      service.refresh()
    }
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

  component ControlButton: BorderSurface {
    id: controlButton
    required property var panel
    property string label: ""
    property string targetKey: ""
    property bool selected: false
    readonly property bool actionable: targetKey !== "" && panel.controllable
    readonly property bool hot: actionable && (buttonMouse.containsMouse || panel.targetSelected(targetKey))
    signal clicked()

    width: Math.max(Style.space(28), buttonLabel.implicitWidth + Style.space(12))
    height: Style.space(24)
    radius: Style.cornerRadius
    color: hot ? Style.hoverFillFor(panel.foreground, panel.foreground)
      : (selected ? Style.selectedFillFor(panel.foreground, Color.accent) : "transparent")
    borderSpec: hot ? Border.controlSpec("hover-cursor", panel.foreground, panel.foreground) : Border.none()

    Text {
      id: buttonLabel
      anchors.centerIn: parent
      text: controlButton.label
      color: controlButton.panel.foreground
      opacity: controlButton.panel.connected ? 1 : 0.5
      font.family: controlButton.panel.fontFamily
      font.pixelSize: Style.font.body
      font.bold: controlButton.selected
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: controlButton.targetKey !== ""
      cursorShape: controlButton.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: controlButton.panel.select(controlButton.targetKey)
      onClicked: if (controlButton.actionable) controlButton.clicked()
    }
  }

  component ControlGroup: BorderSurface {
    id: controlGroup
    required property var panel
    default property alias content: groupRow.data
    implicitWidth: groupRow.implicitWidth + Style.space(4)
    implicitHeight: groupRow.implicitHeight + Style.space(4)
    radius: Style.cornerRadius
    color: Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, 0.04)
    borderSpec: Border.flat(Qt.rgba(panel.foreground.r, panel.foreground.g, panel.foreground.b, 0.10), 1)

    Row {
      id: groupRow
      anchors.centerIn: parent
      spacing: Style.space(2)
    }
  }

  component ControlRow: CursorSurface {
    id: controlRow
    required property var panel
    required property var modelData
    readonly property string rowKey: modelData.key
    readonly property bool isToggle: modelData.kind === "toggle"
    readonly property bool isPreset: modelData.kind === "preset"

    x: Style.space(8)
    width: Math.max(0, (parent ? parent.width : 0) - Style.space(16))
    implicitHeight: rowContent.implicitHeight + Style.space(12)
    hasCursor: isToggle && panel.targetSelected(rowKey)
    foreground: panel.foreground
    accent: panel.foreground

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: controlRow.isToggle
      cursorShape: controlRow.panel.controllable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: controlRow.panel.select(controlRow.rowKey)
      onClicked: controlRow.panel.toggle(controlRow.modelData)
    }

    Column {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(6)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: Style.space(22)
          anchors.verticalCenter: parent.verticalCenter
          text: String.fromCodePoint(controlRow.modelData.icon)
          color: controlRow.panel.foreground
          opacity: controlRow.panel.rowActive(controlRow.modelData) ? 1 : 0.45
          font.family: controlRow.panel.fontFamily
          font.pixelSize: Style.font.icon
          horizontalAlignment: Text.AlignHCenter
        }

        Column {
          width: Math.max(0, parent.width - Style.space(32) - trailing.width - parent.spacing)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: controlRow.modelData.primaryText
            textFormat: Text.PlainText
            color: controlRow.panel.foreground
            font.family: controlRow.panel.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: controlRow.panel.rowValue(controlRow.modelData)
            textFormat: Text.PlainText
            color: controlRow.panel.mutedColor
            font.family: controlRow.panel.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Item {
          id: trailing
          readonly property Item control: controlRow.isToggle ? toggleSwitch : (controlRow.isPreset ? presetStepper : modes)
          anchors.verticalCenter: parent.verticalCenter
          width: control.implicitWidth
          height: control.implicitHeight

          ToggleSwitch {
            id: toggleSwitch
            visible: controlRow.isToggle
            checked: controlRow.panel.rowActive(controlRow.modelData)
            interactive: false
            busy: controlRow.panel.service !== null && controlRow.panel.service.busy
            opacity: controlRow.panel.connected ? 1 : 0.5
            foreground: controlRow.panel.foreground
          }

          ControlGroup {
            id: modes
            visible: !controlRow.isToggle && !controlRow.isPreset
            panel: controlRow.panel

            Repeater {
              model: controlRow.isToggle || controlRow.isPreset ? [] : controlRow.modelData.choices

              ControlButton {
                required property string modelData
                panel: controlRow.panel
                label: controlRow.panel.choiceLabel(modelData)
                targetKey: controlRow.rowKey + ":" + modelData
                selected: controlRow.panel.connected && controlRow.panel.service[controlRow.modelData.property] === modelData
                onClicked: controlRow.panel.setChoice(controlRow.modelData, modelData)
              }
            }
          }

          ControlGroup {
            id: presetStepper
            visible: controlRow.isPreset
            panel: controlRow.panel

            ControlButton {
              panel: controlRow.panel
              label: "‹"
              targetKey: controlRow.isPreset ? controlRow.rowKey + ":previous" : ""
              onClicked: controlRow.panel.cyclePreset(controlRow.modelData, -1)
            }
            ControlButton {
              panel: controlRow.panel
              label: controlRow.isPreset && controlRow.panel.connected ? controlRow.panel.choiceLabel(controlRow.panel.service.eqPreset) : ""
            }
            ControlButton {
              panel: controlRow.panel
              label: "›"
              targetKey: controlRow.isPreset ? controlRow.rowKey + ":next" : ""
              onClicked: controlRow.panel.cyclePreset(controlRow.modelData, 1)
            }
          }
        }
      }

      // The level only applies in custom mode, so the slider and stepper stay
      // disabled for off and adaptive.
      Row {
        id: levelRow
        visible: controlRow.modelData.kind === "transparency"
        readonly property bool custom: controlRow.panel.transparencyMode === "custom"
        x: Style.space(32)
        width: parent.width - Style.space(32)
        spacing: Style.space(10)

        PanelSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - stepper.implicitWidth - parent.spacing)
          bar: controlRow.panel.panelBar
          minimum: 0
          maximum: 100
          step: 5
          value: controlRow.panel.transparencyLive
          enabled: controlRow.panel.controllable && levelRow.custom
          opacity: enabled ? 1 : 0.5
          onMoved: function(value) {
            controlRow.panel.select("transparency:decrement")
            controlRow.panel.setTransparency(Math.round(value))
          }
        }

        ControlGroup {
          id: stepper
          anchors.verticalCenter: parent.verticalCenter
          panel: controlRow.panel
          opacity: levelRow.custom ? 1 : 0.5

          ControlButton {
            panel: controlRow.panel
            label: "−"
            targetKey: levelRow.custom ? "transparency:decrement" : ""
            onClicked: controlRow.panel.stepTransparency(-1)
          }
          ControlButton {
            panel: controlRow.panel
            label: Math.round(controlRow.panel.transparencyLive) + "%"
          }
          ControlButton {
            panel: controlRow.panel
            label: "+"
            targetKey: levelRow.custom ? "transparency:increment" : ""
            onClicked: controlRow.panel.stepTransparency(1)
          }
        }
      }

      // One slider per band. The value button resets its band to 0 dB.
      Repeater {
        model: controlRow.isPreset ? controlRow.panel.eqLive.length : 0

        Row {
          id: bandRow
          required property int index
          x: Style.space(32)
          width: parent.width - Style.space(32)
          spacing: Style.space(10)

          Text {
            width: Style.space(48)
            anchors.verticalCenter: parent.verticalCenter
            text: controlRow.panel.eqBandLabels[bandRow.index]
            color: controlRow.panel.mutedColor
            font.family: controlRow.panel.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSlider {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - Style.space(48) - bandValue.width - parent.spacing * 2)
            bar: controlRow.panel.panelBar
            minimum: -controlRow.panel.eqGainLimit
            maximum: controlRow.panel.eqGainLimit
            step: controlRow.panel.eqGainStep
            value: controlRow.panel.eqLive[bandRow.index]
            enabled: controlRow.panel.controllable
            opacity: enabled ? 1 : 0.5
            onMoved: function(value) {
              controlRow.panel.select("eq-band:" + bandRow.index)
              controlRow.panel.setEqBand(bandRow.index, value)
            }
          }

          ControlButton {
            id: bandValue
            width: Style.space(64)
            anchors.verticalCenter: parent.verticalCenter
            panel: controlRow.panel
            label: controlRow.panel.eqGainLabel(controlRow.panel.eqLive[bandRow.index])
            targetKey: "eq-band:" + bandRow.index
            onClicked: controlRow.panel.setEqBand(bandRow.index, 0)
          }
        }
      }
    }
  }

  Connections {
    target: root.service
    function onCustomTransparencyChanged() {
      if (!transparencyDebounce.running) root.transparencyLive = root.service.customTransparency
    }
    function onEqChanged() {
      if (!eqDebounce.running) root.eqLive = root.service.eq ? root.service.eq.slice() : []
    }
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
      height: Math.min(contentColumn.implicitHeight + Style.space(32), Style.space(670), parent.height - Style.space(32))
      color: Color.background
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      // FilterablePanel leaves Left and Right unhandled, so they reach this
      // item and adjust the transparency or choice row under the cursor.
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
          navigationModel: root.buildNavigationEntries(filteredModel)
          onActivateRequested: function(entry) { root.activateEntry(entry) }
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
                title: filterController.filterText || "Headphones"
                meta: root.heroMeta()
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconOpacity: root.connected ? 1 : 0.5
                iconComponent: Component {
                  Text {
                    text: String.fromCodePoint(root.connected ? 0xf02cb : 0xf07ce)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                  }
                }
                trailingControl: Component {
                  Row {
                    visible: root.connected && root.service.battery >= 0
                    spacing: Style.space(4)
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.batteryIcon(root.service ? root.service.battery : 0)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: (root.service ? root.service.battery : 0) + "%"
                      color: root.mutedColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(2)

                SectionHeading {
                  id: noiseHeading
                  title: "Noise control"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  refreshable: true
                  refreshing: root.service !== null && root.service.busy
                  hasCursor: root.targetSelected("action:refresh")
                  onRefreshHovered: root.select("action:refresh")
                  onRefreshRequested: if (root.service) root.service.refresh()
                }

                Item { width: 1; height: Style.space(4) }

                Repeater {
                  id: noiseRepeater
                  model: root.sectionRows("Noise control")
                  ControlRow { panel: root }
                }
              }

              Column {
                visible: root.sectionRows("Sound").length > 0
                width: parent.width
                spacing: Style.space(2)

                SectionHeading {
                  title: "Sound"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Item { width: 1; height: Style.space(4) }

                Repeater {
                  id: soundRepeater
                  model: root.sectionRows("Sound")
                  ControlRow { panel: root }
                }
              }

              Column {
                visible: root.sectionRows("Behaviour").length > 0
                width: parent.width
                spacing: Style.space(2)

                SectionHeading {
                  title: "Behaviour"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Item { width: 1; height: Style.space(4) }

                Repeater {
                  id: behaviourRepeater
                  model: root.sectionRows("Behaviour")
                  ControlRow { panel: root }
                }
              }

              Text {
                visible: filterController.filterText !== "" && filterController.count === 0
                width: parent.width
                text: "No matches for “" + filterController.filterText + "”"
                textFormat: Text.PlainText
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
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
    onTriggered: if (root.service) root.service.setCustomTransparency(value)
  }

  Timer {
    id: eqDebounce
    interval: 350
    repeat: false
    onTriggered: root.sendEq()
  }
}
