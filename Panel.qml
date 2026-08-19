import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "timmo.momentumctl"

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    controller.show()
    if (service) service.refresh()
    Qt.callLater(function() {
      scrollArea.contentItem.contentY = 0
      keyCatcher.forceActiveFocus()
    })
  }
  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(410))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(650))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          id: contentColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "MOMENTUM 4"
            meta: root.service && root.service.connected
              ? "Connected · Battery " + root.service.battery + "%"
              : (root.service && root.service.error ? root.service.error : "Waiting for headset")
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

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "NOISE CONTROL"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Active noise cancellation"
            description: "Reduce surrounding noise"
            foreground: root.foreground
            fontFamily: root.fontFamily
            checked: root.service ? root.service.anc : false
            enabled: root.service && root.service.connected && !root.service.busy
            onClicked: root.service.setValue("anc", checked ? "off" : "on")
          }

          Toggle {
            width: parent.width
            label: "Adaptive noise control"
            description: "Adjust cancellation to the surroundings"
            foreground: root.foreground
            fontFamily: root.fontFamily
            checked: root.service ? root.service.adaptive : false
            enabled: root.service && root.service.connected && !root.service.busy
            onClicked: root.service.setValue("adaptive", checked ? "off" : "on")
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(transparencyLabel.implicitHeight, transparencyValue.implicitHeight)
              Text {
                id: transparencyLabel
                text: "Transparency"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.left: parent.left
              }
              Text {
                id: transparencyValue
                text: Math.round(transparencySlider.dragging ? transparencySlider.liveValue : (root.service ? root.service.transparency : 0)) + "%"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
              }
            }

            PanelSlider {
              id: transparencySlider
              bar: root.bar
              width: parent.width
              minimum: 0
              maximum: 100
              step: 5
              value: root.service ? root.service.transparency : 0
              enabled: root.service && root.service.connected && !root.service.busy
              onMoved: function(value) {
                transparencyDebounce.value = Math.round(value)
                transparencyDebounce.restart()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "BEHAVIOUR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Smart Pause"
            description: "Pause playback when the headphones are removed"
            foreground: root.foreground
            fontFamily: root.fontFamily
            checked: root.service ? root.service.smartPause : false
            enabled: root.service && root.service.connected && !root.service.busy
            onClicked: root.service.setValue("smart-pause", checked ? "off" : "on")
          }

          Toggle {
            width: parent.width
            label: "On-head detection"
            description: "Detect when the headphones are being worn"
            foreground: root.foreground
            fontFamily: root.fontFamily
            checked: root.service ? root.service.onHeadDetection : false
            enabled: root.service && root.service.connected && !root.service.busy
            onClicked: root.service.setValue("on-head-detection", checked ? "off" : "on")
          }

          Toggle {
            width: parent.width
            label: "Auto-answer"
            description: "Answer calls when the headphones are put on"
            foreground: root.foreground
            fontFamily: root.fontFamily
            checked: root.service ? root.service.autoAnswer : false
            enabled: root.service && root.service.connected && !root.service.busy
            onClicked: root.service.setValue("auto-answer", checked ? "off" : "on")
          }

          Toggle {
            width: parent.width
            label: "Comfort Call"
            description: "Adjust call audio for comfort"
            foreground: root.foreground
            fontFamily: root.fontFamily
            checked: root.service ? root.service.comfortCall : false
            enabled: root.service && root.service.connected && !root.service.busy
            onClicked: root.service.setValue("comfort-call", checked ? "off" : "on")
          }

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "ANTI-WIND"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: ["off", "auto", "max"]
              Button {
                required property string modelData
                width: (contentColumn.width - Style.space(16)) / 3
                text: modelData.toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
                active: root.service && root.service.antiWind === modelData
                enabled: root.service && root.service.connected && !root.service.busy
                onClicked: root.service.setValue("anti-wind", modelData)
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
