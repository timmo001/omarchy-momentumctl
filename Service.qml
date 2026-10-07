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
  // Null when the firmware doesn't support it.
  property var bassBoost: null
  property var touchControls: null
  // "never" or minutes as a string, matching the panel's choices.
  property var autoPowerOff: null
  property string firmware: ""
  // Gains in dB per band, and the matching preset or "custom".
  property var eq: null
  property var eqPreset: null
  property int transparency: 0
  // The level the headset reports while adaptive is on is its own, so the
  // last custom level is kept separately for the slider.
  property int customTransparency: 0
  property bool statusValid: false
  readonly property string transparencyMode: !anc ? "off" : (adaptive ? "adaptive" : "custom")
  property var pendingCommands: []

  function parseStatus(text) {
    var values
    try {
      values = JSON.parse(String(text || ""))
    } catch (e) {
      return false
    }
    if (!values || !isFinite(values.battery) || !isFinite(values.transparency)) return false
    battery = Math.max(0, Math.min(100, Math.round(values.battery)))
    transparency = Math.max(0, Math.min(100, Math.round(values.transparency)))
    anc = values.anc === true
    adaptive = values.adaptive === true
    antiWind = String(values.antiWind || "off")
    autoAnswer = values.autoAnswer === true
    comfortCall = values.comfortCall === true
    onHeadDetection = values.onHeadDetection === true
    smartPause = values.smartPause === true
    bassBoost = typeof values.bassBoost === "boolean" ? values.bassBoost : null
    touchControls = typeof values.touchControls === "boolean" ? values.touchControls : null
    autoPowerOff = !isFinite(values.autoPowerOff) || values.autoPowerOff === null ? null : (values.autoPowerOff === 0 ? "never" : String(values.autoPowerOff))
    firmware = values.firmware ? String(values.firmware) : ""
    eq = Array.isArray(values.eq) ? values.eq : null
    eqPreset = eq === null ? null : String(values.eqPreset || "custom")
    if (!adaptive) customTransparency = transparency
    return true
  }

  // The CLI prints "momentum: <reason>" on failure.
  function cliError(text, fallback) {
    var message = String(text || "").trim().split("\n").pop().replace(/^momentum: /, "")
    return message || fallback
  }

  function refresh() {
    if (!statusProcess.running && !controlProcess.running) statusProcess.running = true
  }

  function setValue(setting, value) {
    setValues([[setting, value]])
  }

  // Runs one momentum invocation at a time and stops at the first failure,
  // because each call opens its own RFCOMM session.
  function setValues(commands) {
    if (busy || commands.length === 0) return
    error = ""
    pendingCommands = commands.slice(1)
    busy = true
    runCommand(commands[0])
  }

  function runCommand(command) {
    controlProcess.command = ["momentum", "set"].concat(command.map(String))
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
    command: ["bash", "-lc", "command -v momentum"]
    running: true
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.available = exitCode === 0
      if (root.available) root.refresh()
      else root.error = "momentum is not installed"
    }
  }

  Process {
    id: statusProcess
    command: ["momentum", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.statusValid = root.parseStatus(text)
    }
    stderr: StdioCollector {
      id: statusErrors
      waitForEnd: true
    }
    onRunningChanged: if (running) {
      root.busy = true
      root.statusValid = false
    }
    onExited: function(exitCode) {
      root.busy = false
      root.connected = exitCode === 0 && root.statusValid
      root.error = root.connected ? "" : root.cliError(statusErrors.text, "The headset is unavailable")
    }
  }

  Process {
    id: controlProcess
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: controlErrors
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.pendingCommands.length > 0) {
        var next = root.pendingCommands[0]
        root.pendingCommands = root.pendingCommands.slice(1)
        root.runCommand(next)
        return
      }
      root.pendingCommands = []
      root.busy = false
      if (exitCode !== 0) root.error = root.cliError(controlErrors.text, "Could not update the headset")
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
