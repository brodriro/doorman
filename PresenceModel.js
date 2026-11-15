.pragma library

// Pure presence logic: no QML, no I/O, so tests/presence.test.js can run it
// under node. Main.qml owns the timer, the collector process and the files;
// everything about who joined or left is decided here.
//
// A network's state:
//   { schema, networkId, baselined, lastScan, devices: { <mac>: Device }, history: [Event] }
// Device:
//   { mac, ip, name, alias, firstSeen, lastSeen, present, randomMac, isGateway, isSelf }
// Event:
//   { type: "joined" | "left", mac, ip, name, ts, returning }

var SCHEMA = 1
var MAX_DEVICES = 512
var MAX_HISTORY = 200
var MAX_TEXT = 64

var MAC_RE = /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/
var IP_RE = /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/
var NETWORK_ID_RE = /^[0-9a-f]{12}$/

function text(value) {
  if (value === null || value === undefined) return null
  var s = String(value).replace(/[\u0000-\u001f\u007f]/g, "").slice(0, MAX_TEXT)
  return s === "" ? null : s
}

function isNetworkId(value) {
  return typeof value === "string" && NETWORK_ID_RE.test(value)
}

function isMac(value) {
  return typeof value === "string" && MAC_RE.test(value)
}

function emptyState(networkId) {
  return { schema: SCHEMA, networkId: networkId, baselined: false, lastScan: 0, devices: {}, history: [] }
}

// Accepts whatever came off disk and returns a well-formed state for
// networkId, dropping anything that does not validate.
function normalizeState(raw, networkId) {
  var state = emptyState(networkId)
  if (!raw || typeof raw !== "object" || raw.schema !== SCHEMA || raw.networkId !== networkId) return state

  state.baselined = raw.baselined === true
  state.lastScan = Number(raw.lastScan) || 0

  var devices = raw.devices && typeof raw.devices === "object" ? raw.devices : {}
  var macs = Object.keys(devices)
  for (var i = 0; i < macs.length && i < MAX_DEVICES; i++) {
    var d = devices[macs[i]]
    if (!d || !MAC_RE.test(macs[i]) || d.mac !== macs[i]) continue
    state.devices[d.mac] = {
      mac: d.mac,
      ip: IP_RE.test(String(d.ip)) ? d.ip : null,
      name: text(d.name),
      alias: text(d.alias),
      firstSeen: Number(d.firstSeen) || 0,
      lastSeen: Number(d.lastSeen) || 0,
      present: d.present === true,
      randomMac: d.randomMac === true,
      isGateway: d.isGateway === true,
      isSelf: d.isSelf === true,
      blocked: d.blocked === true
    }
  }

  var history = Array.isArray(raw.history) ? raw.history : []
  for (var j = Math.max(0, history.length - MAX_HISTORY); j < history.length; j++) {
    var e = history[j]
    if (!e || (e.type !== "joined" && e.type !== "left") || !MAC_RE.test(String(e.mac))) continue
    state.history.push({
      type: e.type,
      mac: e.mac,
      ip: IP_RE.test(String(e.ip)) ? e.ip : null,
      name: text(e.name),
      ts: Number(e.ts) || 0,
      returning: e.returning === true
    })
  }
  return state
}

// Validates one collector snapshot. Returns null when it is unusable.
function parseScan(output) {
  var scan
  try {
    scan = JSON.parse(String(output || ""))
  } catch (e) {
    return null
  }
  if (!scan || scan.schema !== SCHEMA || !scan.network || !isNetworkId(scan.network.id) || !Array.isArray(scan.devices))
    return null

  var devices = []
  var seen = {}
  for (var i = 0; i < scan.devices.length && devices.length < MAX_DEVICES; i++) {
    var d = scan.devices[i]
    if (!d || !MAC_RE.test(String(d.mac)) || seen[d.mac]) continue
    seen[d.mac] = true
    devices.push({
      mac: d.mac,
      ip: IP_RE.test(String(d.ip)) ? d.ip : null,
      name: text(d.name),
      randomMac: d.randomMac === true,
      isGateway: d.isGateway === true,
      isSelf: d.isSelf === true
    })
  }

  return {
    ts: Number(scan.ts) || 0,
    network: {
      id: scan.network.id,
      iface: text(scan.network.iface),
      wireless: scan.network.wireless === true,
      ssid: text(scan.network.ssid),
      subnet: text(scan.network.subnet),
      gateway: IP_RE.test(String(scan.network.gateway)) ? scan.network.gateway : null
    },
    devices: devices
  }
}

function copyState(state) {
  var next = emptyState(state.networkId)
  next.baselined = state.baselined
  next.lastScan = state.lastScan
  next.history = state.history.slice()
  var macs = Object.keys(state.devices)
  for (var i = 0; i < macs.length; i++) {
    var d = state.devices[macs[i]]
    var c = {}
    for (var k in d) c[k] = d[k]
    next.devices[macs[i]] = c
  }
  return next
}

function event(type, device, ts, returning) {
  return { type: type, mac: device.mac, ip: device.ip, name: device.alias || device.name, ts: ts, returning: returning }
}

// Folds one scan into the state.
//   options.graceSec   a present device must be missing this long to count as gone
//   options.staleSec   a gap between scans longer than this (suspend, being on
//                      another network) re-baselines silently instead of
//                      reporting everyone who changed meanwhile
// Returns { state, events, silent }. `events` is what to announce; it is empty
// when the scan was silent, though history and presence are still updated.
function applyScan(state, scan, options) {
  var graceSec = Math.max(0, Number(options && options.graceSec) || 0)
  var staleSec = Math.max(graceSec, Number(options && options.staleSec) || 0)
  var now = scan.ts
  var next = copyState(state)
  var silent = !state.baselined || (state.lastScan > 0 && now - state.lastScan > staleSec)
  var events = []
  var inScan = {}

  for (var i = 0; i < scan.devices.length; i++) {
    var s = scan.devices[i]
    inScan[s.mac] = true
    var d = next.devices[s.mac]
    if (!d) {
      d = next.devices[s.mac] = {
        mac: s.mac, ip: s.ip, name: s.name, alias: null,
        firstSeen: now, lastSeen: now, present: true,
        randomMac: s.randomMac, isGateway: s.isGateway, isSelf: s.isSelf,
        blocked: false
      }
      if (!silent) events.push(event("joined", d, now, false))
    } else {
      var wasPresent = d.present
      d.ip = s.ip || d.ip
      d.name = s.name || d.name
      d.lastSeen = now
      d.present = true
      d.randomMac = s.randomMac
      d.isGateway = s.isGateway
      d.isSelf = s.isSelf
      if (!wasPresent && !silent) events.push(event("joined", d, now, true))
    }
  }

  var macs = Object.keys(next.devices)
  for (var j = 0; j < macs.length; j++) {
    var gone = next.devices[macs[j]]
    if (inScan[gone.mac] || !gone.present) continue
    if (silent || now - gone.lastSeen >= graceSec) {
      gone.present = false
      if (!silent) events.push(event("left", gone, now, false))
    }
  }

  next.baselined = true
  next.lastScan = now
  next.history = next.history.concat(events)
  if (next.history.length > MAX_HISTORY) next.history = next.history.slice(next.history.length - MAX_HISTORY)
  pruneDevices(next)

  return { state: next, events: events, silent: silent }
}

// Keeps the device table bounded: forget the longest-absent devices first,
// but never one the user has annotated (an alias, or a block mark they want
// to keep around to copy into the router).
function pruneDevices(state) {
  var macs = Object.keys(state.devices)
  if (macs.length <= MAX_DEVICES) return
  var removable = macs
    .map(function(m) { return state.devices[m] })
    .filter(function(d) { return !d.present && !d.alias && !d.blocked })
    .sort(function(a, b) { return a.lastSeen - b.lastSeen })
  for (var i = 0; i < removable.length && Object.keys(state.devices).length > MAX_DEVICES; i++)
    delete state.devices[removable[i].mac]
}

function setAlias(state, mac, alias) {
  if (!state.devices[mac]) return state
  var next = copyState(state)
  next.devices[mac].alias = text(alias)
  return next
}

// Marks a device the user considers unauthorized. This never touches the
// network — the plugin is passive. The flag only drives the panel marking so
// the user can copy the MAC into the router's own blocklist by hand.
function setBlocked(state, mac, blocked) {
  if (!state.devices[mac]) return state
  var next = copyState(state)
  next.devices[mac].blocked = blocked === true
  return next
}

// Devices for display: present first, then by IP.
function deviceList(state) {
  var list = Object.keys(state.devices).map(function(m) { return state.devices[m] })
  function ipKey(ip) {
    if (!ip) return Infinity
    var p = ip.split(".")
    return ((+p[0] * 256 + +p[1]) * 256 + +p[2]) * 256 + +p[3]
  }
  list.sort(function(a, b) {
    if (a.present !== b.present) return a.present ? -1 : 1
    return ipKey(a.ip) - ipKey(b.ip)
  })
  return list
}

function displayName(device) {
  return device ? (device.alias || device.name || null) : null
}

// Notification bodies may be rendered as markup by the daemon: strip the
// characters that could open a tag or entity.
function notifySafe(value) {
  return String(value === null || value === undefined ? "" : value).replace(/[<>&\u0000-\u001f\u007f]/g, "").slice(0, MAX_TEXT)
}

// mode: "off" | "new" (first-time joins only) | "all"
function eventsToNotify(events, mode) {
  if (mode === "off") return []
  if (mode === "new") return events.filter(function(e) { return e.type === "joined" && !e.returning })
  return events.slice()
}
