# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project goal

**Doorman** (`xaiovz.doorman`) is an **Omarchy shell plugin** that monitors who joins and leaves the Wi-Fi network the machine is currently connected to: it keeps a live list of devices on the LAN, notices when a device appears or disappears, and surfaces that in the Omarchy bar (and as desktop notifications).

The repo directory is still named `wifi-monitor`; the plugin id, state dir (`~/.local/state/omarchy/doorman/`) and scripts use `doorman`. Platform facts below were verified against the Omarchy install on this machine (`/usr/share/omarchy`, `$OMARCHY_PATH`).

## Platform: Omarchy shell plugins

The bar, notifications, and overlays all run inside one long-lived Quickshell process, `omarchy-shell`. Plugins are QML loaded into that process — **unsandboxed**, so treat everything they read (command output, `ip neigh`, hostnames from mDNS/DHCP, settings) as untrusted.

Authoritative references (read these rather than guessing APIs):
- `$OMARCHY_PATH/default/agents/skills/omarchy/plugins.md` — plugin UI safety, motion, i18n, bar layout rules.
- `$OMARCHY_PATH/shell/plugins/README.md` — manifest contract and the kinds/entry points of first-party plugins.
- `$OMARCHY_PATH/shell/plugins/panels/network/` — first-party network bar widget (closest UI analogue).
- `$OMARCHY_PATH/shell/plugins/services/battery/` — minimal `service` plugin (background logic + notifications).
- `~/.config/omarchy/plugins/xaiovz.agents/` — this user's own bar-widget plugin; good model for the Main.qml / Panel.qml split, `Process` + `StdioCollector`, `FileView` watching, settings `schema`, and a `bin/` of helper scripts.
- `$OMARCHY_PATH/bin/omarchy-plugin-validate` — exact checks the shell enforces on a manifest.

### Manifest essentials (`manifest.json` at repo root)
- `schemaVersion` must be the number `1`; required: `id`, `name`, `version`, `kinds`, `entryPoints`.
- `id` must not use the reserved `omarchy.*` namespace (use e.g. `xaiovz.doorman`).
- Every kind needs its entry point: `bar-widget` → `entryPoints.barWidget`, `service` → `entryPoints.service`, `panel` → `entryPoints.panel`.
- Entry points are relative paths with no `..`. **No symlinks anywhere inside the plugin folder** (validation fails).
- `barWidget.defaultSection` ∈ `left|centerBegin|center|centerEnd|tray|right`; user-tunable options go in `barWidget.defaults` + `barWidget.schema` (see agents manifest).

### Architecture
Data flows one way: `bin/doorman-scan` (JSON snapshot) → `Main.qml` (timer, per-network state on disk, `PresenceModel.js` decides joins/leaves) → `Service.qml` → `Panel.qml`.
- **`Service.qml` (kind `service`)** — one instance per shell. Owns `Main` and the notifications (`Quickshell.execDetached` with an argv array to `omarchy-notification-send`, text passed through `Presence.notifySafe`). Tracks `unseenNew`/`newMacs` until the panel closes. `copyMac(mac)` copies a validated MAC to the clipboard (`wl-copy`, argv) so the user can paste it into the router blocklist; `setBlocked(mac, bool)` forwards to `Main`.
- **`Panel.qml` (kind `bar-widget`)** — instantiated **once per monitor** (this machine has 2), so it must stay stateless: it reaches the service with `bar.shell.serviceFor("xaiovz.doorman")` and pushes its `settings` (from the shell.json widget entry) into it via `Binding`. Never put scanning or notifications in Panel.qml or they run once per monitor. Layout follows the Figma proposals (`docs/diseno-figma.md`, local/gitignored): hero icon tile, counter chips, per-device type-icon tile + state badge, uppercase section headers with counts, and a top **Flagged** alert section. Two reusable inline components live here — `Pill` (chips/badges) and `IconTile` (hero/rows). All colours come from live theme roles (`accent`/`urgent`/`foreground`, `root.neutral`); never hardcode a colour — the shell themes the plugin at runtime and `Color` only guarantees `foreground/background/accent/urgent/muted` (no yellow/green/red).
- Strings in `i18n/{en,es}.json`, read via `Commons.Translations` (the shell's language decides; currently English).
- Collector is unprivileged by design: `arp-scan`/`nmap` are not installed; presence comes from a ping sweep + `ip neigh`, names from `avahi-browse`. **Flagging is passive**: a user-set `blocked` flag per device (in state, not the scan) only drives the UI and the copy-MAC action — the plugin never deauths, disconnects, or attacks a device; blocking is the user's job in the router.

### Rules from Omarchy's plugin guide that apply here
- Bind every dynamic string (hostnames, vendor names, SSIDs) with `textFormat: Text.PlainText` — device names on a LAN are attacker-controlled.
- Never interpolate untrusted values into shell commands; pass them as separate `Process.command` array elements.
- Bound sizes: cap device count, string lengths, and history length.
- Animations: `Style.duration(ms)`, ease-out only, <300ms. Strings via `Commons.Translations` with `i18n/en.json` (add `es.json` too).

## Commands

```bash
# Validate the plugin folder (run before installing/publishing)
omarchy-plugin-validate .

# Install for local dev: validates, copies (symlinks are rejected) and rescans
./install.sh            # add --enable the first time

# Open/close the panel without clicking (index = position in the bar section)
qs ipc -i "$(qs list --all | awk '/^Instance/{print $2; exit}' | tr -d :)" call shell togglePanelAt right 1

# Shell log (plugin QML errors land here)
qs log -i <instance> | grep -i doorman

# Enable / disable / list
omarchy plugin enable <plugin-id> --section right
omarchy plugin disable <plugin-id>
omarchy plugin list

# Restart the shell if a change does not apply; QML errors appear in the shell's log
omarchy restart shell

# Install from git (how end users will get it)
omarchy plugin add <git-url> --enable
```

Saving files under `~/.config/omarchy/plugins/` hot-reloads plugin code; bar layout lives in `~/.config/omarchy/shell.json` (also hot-reloaded). Never edit files under `$OMARCHY_PATH` — that is the packaged Omarchy install.

### Collector (`bin/doorman-scan`)

```bash
bin/doorman-scan | jq            # live scan (ping sweep of own /24, ~5 s)
bin/doorman-scan --no-sweep      # passive: neighbor table + mDNS only
tests/run.sh                          # all fixture tests
tests/run.sh wifi-basic               # one fixture
```

`WM_FIXTURE_DIR=<dir>` swaps every live command for files in that dir (`route.txt`, `addr.json`, `neigh.json`, `mac.txt`, `avahi.txt`, `wifi.txt`) and `WM_NOW` pins the timestamp; each fixture's `expected.json` is the golden output. To add a case: create the dir, then generate `expected.json` with those env vars and review it by hand. Output contract: `schema: 1`, `network` (`id` = gateway MAC without colons, identifies the network), `devices[]` keyed by `mac`, with `isSelf`/`isGateway`/`randomMac` flags; names are already sanitized (charset + 64 chars), but QML must still render them as `PlainText`.

### Presence logic (`PresenceModel.js` + `Main.qml`)

```bash
node --test tests/                    # PresenceModel.js unit tests
node --test --test-name-pattern grace tests/   # one test
tests/harness.sh 30                   # run Main.qml under qs for 30 s against the live LAN (throwaway state dir)
```

- `PresenceModel.js` is a `.pragma library` with **all** join/leave decisions and no QML/I/O; the node tests load it through `vm` (strip the pragma). Keep logic there, not in QML. Values from the vm have a foreign `Array` prototype — compare via `JSON` copies. Device fields include `alias` and `blocked` (both user-set, persisted); `setAlias`/`setBlocked` return a new state (copy-on-write) and `isMac` validates a MAC. A `blocked` device is never pruned.
- Rules: first scan of a network is a silent baseline; a device "leaves" only after `absenceGraceSec`; a gap between scans > `staleSec` (suspend, other network) re-baselines silently; events carry the alias if set.
- `Main.qml` runs the collector on a timer, keeps one state file per network at `$XDG_STATE_HOME/omarchy/doorman/<networkId>.json` (loaded via `FileView` when `networkId` changes; scans arriving meanwhile wait in `pendingScan`), and emits `presenceEvents(events)`. Writes are deferred with `Qt.callLater` — writing inside `onLoaded` makes FileView drop the operation.
- In QML, `onDevicesChanged` can fire before `presentCount` re-evaluates; observe `presentCountChanged` instead.

