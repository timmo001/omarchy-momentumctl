import QtQuick
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property bool available: false
  property bool connected: false
  property bool busy: false
  property string error: ""
  property int battery: -1
  property bool anc: false
  property bool adaptive: false
  property string antiWind: "off"
  property bool autoAnswer: false
  property bool comfortCall: false
  property bool onHeadDetection: false
  property bool smartPause: false
  property int transparency: 0
  property bool statusValid: false

  function parseStatus(text) {
    var values = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var separator = lines[i].indexOf(":")
      if (separator < 0) continue
      values[lines[i].slice(0, separator).trim()] = lines[i].slice(separator + 1).trim()
    }
    if (values.Battery === undefined || values.ANC === undefined) return false
    var nextBattery = Number(String(values.Battery).replace("%", ""))
    var nextTransparency = Number(String(values.Transparency || "0").replace("%", ""))
    if (!isFinite(nextBattery) || !isFinite(nextTransparency)) return false
    battery = Math.max(0, Math.min(100, Math.round(nextBattery)))
    transparency = Math.max(0, Math.min(100, Math.round(nextTransparency)))
    anc = values.ANC === "on"
    adaptive = values.Adaptive === "on"
    antiWind = String(values["Anti-wind"] || "off")
    autoAnswer = values["Auto-answer"] === "on"
    comfortCall = values["Comfort call"] === "on"
    onHeadDetection = values["On-head detection"] === "on"
    smartPause = values["Smart pause"] === "on"
    return true
  }

  function refresh() {
    if (!statusProcess.running && !controlProcess.running) statusProcess.running = true
  }

  function setValue(setting, value) {
    if (busy) return
    error = ""
    controlProcess.command = ["momentumctl", "set", setting, String(value)]
    busy = true
    controlProcess.running = true
  }

  Process {
    id: commandCheck
    command: ["bash", "-lc", "command -v momentumctl"]
    running: true
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.available = exitCode === 0
      if (root.available) root.refresh()
      else root.error = "momentumctl is not installed"
    }
  }

  Process {
    id: statusProcess
    command: ["momentumctl", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.statusValid = root.parseStatus(text)
    }
    onRunningChanged: if (running) {
      root.busy = true
      root.statusValid = false
    }
    onExited: function(exitCode) {
      root.busy = false
      root.connected = exitCode === 0 && root.statusValid
      root.error = root.connected ? "" : "MOMENTUM 4 is unavailable"
    }
  }

  Process {
    id: controlProcess
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) root.error = "Could not update the headset"
      refreshTimer.restart()
    }
  }

  Timer {
    id: refreshTimer
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 30000
    running: root.available
    repeat: true
    onTriggered: root.refresh()
  }
}
