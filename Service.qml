import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "PresenceModel.js" as Presence

// One instance per shell (the bar widget exists once per monitor): owns the
// scanner and the notifications so neither runs twice. Bar widgets reach it
// with bar.shell.serviceFor("xaiovz.doorman") and push their settings in.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property alias monitor: monitor
  readonly property var network: monitor.network
  readonly property var devices: monitor.devices
  readonly property var history: monitor.history
  readonly property bool scanning: monitor.scanning
  readonly property string lastError: monitor.lastError
  readonly property double lastScanMs: monitor.lastScanMs

  // First-time joins nobody has looked at yet; the bar icon lights up until
  // the panel is opened.
  property int unseenNew: 0
  // MACs of those joins, so the panel can highlight them.
  property var newMacs: ({})

  readonly property string notifyMode: {
    var mode = String(settings && settings.notify || "all").toLowerCase()
    return mode === "off" || mode === "new" ? mode : "all"
  }

  function refresh() { monitor.refresh() }
  function setAlias(mac, alias) { monitor.setAlias(mac, alias) }
  function setBlocked(mac, blocked) { monitor.setBlocked(mac, blocked) }

  // Whether wl-copy is installed; probed once at startup (static argv to sh,
  // no interpolation).
  property bool clipboardReady: false
  Process {
    command: ["sh", "-c", "command -v wl-copy >/dev/null 2>&1"]
    running: true
    onExited: function(code) { root.clipboardReady = (code === 0) }
  }

  // Copies a MAC to the clipboard so the user can paste it into the router's
  // blocklist. argv form, and the MAC is validated hex, so nothing from the
  // network reaches a shell. Confirms on success; if wl-copy is missing it
  // says so instead of failing silently.
  function copyMac(mac) {
    if (!Presence.isMac(mac)) return
    if (!clipboardReady) {
      send(strings.t("notify.clipboardMissingTitle"), strings.t("notify.clipboardMissingBody"), "normal")
      return
    }
    Quickshell.execDetached(["wl-copy", "--", mac])
    send(strings.t("notify.copiedTitle"), mac, "low")
  }
  function markSeen() {
    unseenNew = 0
    newMacs = ({})
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Main {
    id: monitor
    settings: root.settings
    onPresenceEvents: function(events) { root.handleEvents(events) }
  }

  function handleEvents(events) {
    var macs = ({})
    for (var k in newMacs) macs[k] = true
    for (var i = 0; i < events.length; i++) {
      if (events[i].type === "joined" && !events[i].returning) {
        unseenNew++
        macs[events[i].mac] = true
      }
    }
    newMacs = macs

    var toNotify = Presence.eventsToNotify(events, notifyMode)
    if (toNotify.length === 0) return

    // A burst (router reboot, many phones waking) becomes one summary.
    if (toNotify.length > 3) {
      var names = toNotify.slice(0, 5).map(function(e) { return describe(e) }).join(", ")
      send(strings.tn("notify.manyTitle", toNotify.length).arg(toNotify.length), names, "normal")
      return
    }
    for (var j = 0; j < toNotify.length; j++) {
      var e = toNotify[j]
      var title = e.type === "left" ? strings.t("notify.leftTitle")
        : e.returning ? strings.t("notify.returnedTitle")
        : strings.t("notify.joinedTitle")
      send(title, describe(e) + (e.ip ? " · " + e.ip : ""), e.type === "joined" && !e.returning ? "normal" : "low")
    }
  }

  function describe(e) {
    return Presence.notifySafe(e.name || strings.t("device.unknown"))
  }

  function send(headline, body, urgency) {
    // argv, never a shell string: names come from the network.
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Doorman", "-g", "󰛳",
                             "-u", urgency, Presence.notifySafe(headline), body])
  }
}
