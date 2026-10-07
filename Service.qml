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
  // The level the headset reports while adaptive is on is its own, so the
  // last custom level is kept separately for the slider.
  property int customTransparency: 0
  property bool statusValid: false
  readonly property string transparencyMode: !anc ? "off" : (adaptive ? "adaptive" : "custom")
  property var pendingCommands: []

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
    if (!adaptive) customTransparency = transparency
    return true
  }

  function refresh() {
    if (!statusProcess.running && !controlProcess.running) statusProcess.running = true
  }

  function setValue(setting, value) {
    setValues([[setting, value]])
  }

  // Runs one momentumctl invocation at a time and stops at the first failure,
  // because each call opens its own RFCOMM session.
  function setValues(commands) {
    if (busy || commands.length === 0) return
    error = ""
    pendingCommands = commands.slice(1)
    busy = true
    runCommand(commands[0])
  }

  function runCommand(command) {
    controlProcess.command = ["momentumctl", "set", command[0], String(command[1])]
    controlProcess.running = true
  }

  function setTransparencyMode(mode) {
    if (mode === transparencyMode) return
    if (mode === "off") setValues([["anc", "off"]])
    else {
      var commands = anc ? [] : [["anc", "on"]]
      if (adaptive !== (mode === "adaptive")) commands.push(["adaptive", mode === "adaptive" ? "on" : "off"])
      setValues(commands)
    }
  }

  function setCustomTransparency(value) {
    var commands = anc ? [] : [["anc", "on"]]
    if (adaptive) commands.push(["adaptive", "off"])
    commands.push(["transparency", value])
    setValues(commands)
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
      root.error = root.connected ? "" : "momentumctl is unavailable"
    }
  }

  Process {
    id: controlProcess
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.pendingCommands.length > 0) {
        var next = root.pendingCommands[0]
        root.pendingCommands = root.pendingCommands.slice(1)
        root.runCommand(next)
        return
      }
      root.pendingCommands = []
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
