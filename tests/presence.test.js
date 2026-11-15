// node --test tests/
// Loads PresenceModel.js (a QML JS library) into a node vm context.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "PresenceModel.js"), "utf8").replace(/^\.pragma library$/m, "")
const P = {}
vm.createContext(P)
vm.runInContext(source, P)
// Values built inside the vm have their own Array prototype; compare plain copies.
const plain = v => JSON.parse(JSON.stringify(v))

const NET = "9c9d7e920c70"
const OPTS = { graceSec: 300, staleSec: 900 }

function dev(n, extra) {
  return Object.assign({ mac: `aa:00:00:00:00:0${n}`, ip: `192.168.31.${n}`, name: null, randomMac: false, isGateway: false, isSelf: false }, extra)
}

function scan(ts, devices) {
  return { ts, network: { id: NET }, devices }
}

function run(state, ts, devices) {
  return P.applyScan(state, scan(ts, devices), OPTS)
}

test("first scan is a silent baseline", () => {
  const r = run(P.emptyState(NET), 1000, [dev(1), dev(2)])
  assert.equal(r.silent, true)
  assert.equal(r.events.length, 0)
  assert.equal(r.state.baselined, true)
  assert.equal(Object.keys(r.state.devices).length, 2)
})

test("new device after baseline joins", () => {
  let r = run(P.emptyState(NET), 1000, [dev(1)])
  r = run(r.state, 1060, [dev(1), dev(2, { name: "phone" })])
  assert.deepEqual(plain(r.events.map(e => [e.type, e.mac, e.name, e.returning])), [["joined", "aa:00:00:00:00:02", "phone", false]])
})

test("missing device leaves only after the grace period", () => {
  let r = run(P.emptyState(NET), 1000, [dev(1), dev(2)])
  r = run(r.state, 1060, [dev(1)])
  assert.equal(r.events.length, 0)
  assert.equal(r.state.devices["aa:00:00:00:00:02"].present, true)
  r = run(r.state, 1300, [dev(1)])
  assert.deepEqual(plain(r.events.map(e => [e.type, e.mac])), [["left", "aa:00:00:00:00:02"]])
  assert.equal(r.state.devices["aa:00:00:00:00:02"].present, false)
})

test("a device that flickers within the grace period never leaves", () => {
  let r = run(P.emptyState(NET), 1000, [dev(1), dev(2)])
  r = run(r.state, 1200, [dev(1)])
  r = run(r.state, 1260, [dev(1), dev(2)])
  r = run(r.state, 1500, [dev(1)])
  assert.equal(r.events.length, 0)
})

test("a known device coming back is a returning join", () => {
  let r = run(P.emptyState(NET), 1000, [dev(1), dev(2)])
  r = run(r.state, 1400, [dev(1)])
  r = run(r.state, 1460, [dev(1), dev(2)])
  assert.deepEqual(plain(r.events.map(e => [e.type, e.returning])), [["joined", true]])
})

test("a long gap between scans re-baselines silently", () => {
  let r = run(P.emptyState(NET), 1000, [dev(1), dev(2)])
  r = run(r.state, 1000 + 3600, [dev(1), dev(3)])
  assert.equal(r.silent, true)
  assert.equal(r.events.length, 0)
  assert.equal(r.state.devices["aa:00:00:00:00:02"].present, false)
  assert.equal(r.state.devices["aa:00:00:00:00:03"].present, true)
  r = run(r.state, 4660, [dev(1), dev(3), dev(4)])
  assert.equal(r.events.length, 1)
})

test("events carry the alias and history is recorded", () => {
  let r = run(P.emptyState(NET), 1000, [dev(1), dev(2)])
  const aliased = P.setAlias(r.state, "aa:00:00:00:00:02", "Tablet de Ana")
  r = run(aliased, 1400, [dev(1)])
  assert.equal(r.events[0].name, "Tablet de Ana")
  assert.equal(r.state.history.length, 1)
  assert.equal(r.state.devices["aa:00:00:00:00:02"].alias, "Tablet de Ana")
})

test("applyScan does not mutate its input", () => {
  const first = run(P.emptyState(NET), 1000, [dev(1)]).state
  const frozen = JSON.stringify(first)
  run(first, 1060, [dev(1), dev(2)])
  assert.equal(JSON.stringify(first), frozen)
})

test("parseScan rejects bad input and sanitizes devices", () => {
  assert.equal(P.parseScan("not json"), null)
  assert.equal(P.parseScan(JSON.stringify({ schema: 1, network: { id: "../etc" }, devices: [] })), null)
  const s = P.parseScan(JSON.stringify({
    schema: 1, ts: 5,
    network: { id: NET, ssid: "x".repeat(100) },
    devices: [
      { mac: "aa:00:00:00:00:01", ip: "192.168.31.1", name: "a\u0000b" },
      { mac: "aa:00:00:00:00:01", ip: "192.168.31.9" },
      { mac: "BAD", ip: "1.2.3.4" },
      { mac: "aa:00:00:00:00:02", ip: "$(rm -rf)" }
    ]
  }))
  assert.equal(s.devices.length, 2)
  assert.equal(s.devices[0].name, "ab")
  assert.equal(s.devices[1].ip, null)
  assert.equal(s.network.ssid.length, 64)
})

test("normalizeState drops state from another network or schema", () => {
  const good = run(P.emptyState(NET), 1000, [dev(1)]).state
  const roundTrip = P.normalizeState(JSON.parse(JSON.stringify(good)), NET)
  assert.deepEqual(JSON.parse(JSON.stringify(roundTrip)), JSON.parse(JSON.stringify(good)))
  assert.equal(Object.keys(P.normalizeState(good, "000000000000").devices).length, 0)
  assert.equal(P.normalizeState({ schema: 2 }, NET).baselined, false)
  assert.equal(P.normalizeState(null, NET).baselined, false)
})

test("deviceList puts present devices first, then by IP", () => {
  let r = run(P.emptyState(NET), 1000, [dev(9), dev(2), dev(5)])
  r = run(r.state, 1400, [dev(9), dev(5)])
  assert.deepEqual(plain(P.deviceList(r.state).map(d => d.ip)), ["192.168.31.5", "192.168.31.9", "192.168.31.2"])
})

test("notification helpers filter by mode and strip markup", () => {
  const events = [
    { type: "joined", returning: false, mac: "a" },
    { type: "joined", returning: true, mac: "b" },
    { type: "left", returning: false, mac: "c" }
  ]
  assert.deepEqual(plain(P.eventsToNotify(events, "off")), [])
  assert.deepEqual(plain(P.eventsToNotify(events, "new").map(e => e.mac)), ["a"])
  assert.equal(P.eventsToNotify(events, "all").length, 3)
  assert.equal(P.notifySafe('<img src="x">&amp;'), 'img src="x"amp;')
  assert.equal(P.notifySafe(null), "")
  assert.equal(P.displayName({ alias: "A", name: "n" }), "A")
  assert.equal(P.displayName({ alias: null, name: null }), null)
})
