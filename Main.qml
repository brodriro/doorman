import QtQuick
import Quickshell
import Quickshell.Io
import "PresenceModel.js" as Presence

// The non-visual half of the plugin: runs bin/doorman-scan on a timer,
// keeps one presence state per network (identified by the gateway's MAC) on
// disk, and announces joins and leaves through presenceEvents(). All decisions
// about who joined or left live in PresenceModel.js.
Item {
  id: root
  visible: false

  property var settings: ({})
  // Lets the owner pause scanning (e.g. while the widget is disabled).
  property bool active: true

  // ------------------------------------------------------------- settings

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function clampInt(value, lo, hi, fallback) {
    var n = Math.round(Number(value))
    return isFinite(n) ? Math.max(lo, Math.min(hi, n)) : fallback
  }

  readonly property int scanIntervalSec: clampInt(setting("scanIntervalSec", 60), 15, 3600, 60)
  readonly property int absenceGraceSec: clampInt(setting("absenceGraceSec", 300), 60, 7200, 300)
  readonly property bool activeSweep: setting("activeSweep", true) !== false
  // Gap between scans that counts as "we were away" (suspend, other network):
  // the next scan re-baselines silently instead of reporting everything.
  readonly property int staleSec: Math.max(absenceGraceSec * 2, scanIntervalSec * 5, 900)

  // ---------------------------------------------------------------- paths

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/doorman"
  readonly property string scanScript: decodeURIComponent(String(Qt.resolvedUrl("bin/doorman-scan")).replace(/^file:\/\//, ""))

  // -------------------------------------------------------- public state

  // Network block of the latest good scan, or null while disconnected.
  property var network: null
  property var devices: []
  property var history: []
  readonly property int presentCount: {
    var n = 0
    for (var i = 0; i < devices.length; i++) if (devices[i].present) n++
    return n
  }
  property string lastError: ""
  property double lastScanMs: 0
  readonly property bool scanning: scanProcess.running

  signal presenceEvents(var events)

  function refresh() {
    if (!root.active || scanProcess.running || !dirReady) return
    var command = [root.scanScript]
    if (!root.activeSweep) command.push("--no-sweep")
    scanProcess.command = command
    scanProcess.running = true
  }

  function setAlias(mac, alias) {
    if (!stateReady || !presenceState) return
    commit(Presence.setAlias(presenceState, mac, alias))
  }

  function setBlocked(mac, blocked) {
    if (!stateReady || !presenceState) return
    commit(Presence.setBlocked(presenceState, mac, blocked))
  }

  // ------------------------------------------------------------ internals

  property var presenceState: null
  property string networkId: ""
  property bool stateReady: false
  property var pendingScan: null
  property bool dirReady: false
  property string scanStderr: ""

  readonly property string stateFilePath: Presence.isNetworkId(networkId) ? stateDir + "/" + networkId + ".json" : ""

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = "cannot create " + root.stateDir
        return
      }
      root.dirReady = true
      root.refresh()
    }
  }

  Timer {
    interval: root.scanIntervalSec * 1000
    running: root.active && root.dirReady
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: scanProcess
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleScanOutput(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.scanStderr = String(text || "").trim().slice(0, 200)
    }

    onExited: function(exitCode) {
      if (exitCode === 0) return
      root.network = null
      root.lastError = root.scanStderr || ("scan failed (exit " + exitCode + ")")
    }
  }

  FileView {
    id: stateFile
    path: root.stateFilePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.stateFileLoaded(text())
    onLoadFailed: root.stateFileLoaded("")
  }

  function handleScanOutput(output) {
    var scan = Presence.parseScan(output)
    if (!scan) return
    root.lastError = ""
    root.network = scan.network
    root.lastScanMs = Date.now()

    if (scan.network.id !== networkId) {
      // Another network: its state has to come off disk before this scan
      // can be compared against it. The FileView loads when its path changes.
      stateReady = false
      presenceState = null
      pendingScan = scan
      networkId = scan.network.id
    } else if (!stateReady) {
      pendingScan = scan
    } else {
      applyScan(scan)
    }
  }

  function stateFileLoaded(content) {
    if (stateReady || !Presence.isNetworkId(networkId)) return
    var raw = null
    try {
      raw = content ? JSON.parse(String(content)) : null
    } catch (e) {
      console.warn("doorman", "Ignoring unreadable state", root.stateFilePath, e)
    }
    presenceState = Presence.normalizeState(raw, networkId)
    stateReady = true
    if (pendingScan && pendingScan.network.id === networkId) {
      var scan = pendingScan
      pendingScan = null
      applyScan(scan)
    } else {
      publish()
    }
  }

  function applyScan(scan) {
    var result = Presence.applyScan(presenceState, scan, { graceSec: absenceGraceSec, staleSec: staleSec })
    commit(result.state)
    if (result.events.length > 0) root.presenceEvents(result.events)
  }

  function commit(state) {
    presenceState = state
    publish()
    // Deferred: a write issued from inside onLoaded races the load operation.
    Qt.callLater(root.saveState)
  }

  function saveState() {
    if (stateReady && presenceState && stateFile.path !== "" && presenceState.networkId === networkId)
      stateFile.setText(JSON.stringify(presenceState) + "\n")
  }

  function publish() {
    devices = presenceState ? Presence.deviceList(presenceState) : []
    history = presenceState ? presenceState.history.slice().reverse() : []
  }
}
