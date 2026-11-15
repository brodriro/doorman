# Doorman

An [Omarchy](https://omarchy.org) shell plugin that watches the local network you are on and tells you who joins and who leaves.

- **Bar icon** with the number of other devices online; it lights up (`3 +1`) when a device never seen before joins, until you open the panel. Right-click scans immediately.
- **Panel**: a hero with the network (SSID or "Wired network", subnet, last scan) and counter chips (online / new / absent), then the devices grouped as **flagged**, online, and seen before, plus recent activity and the scan cadence. Each device has a type icon and a state badge. Click the pencil to give it a name.
- **Flag intruders**: mark a device you don't recognize with the warning button; it moves to a **Flagged** alert section where you can copy its MAC to paste into your router's blocklist. The flag is passive and persists — see below.
- **Notifications** for joins and leaves (configurable), one summary when many change at once.
- Works on Wi-Fi and wired connections; it follows whatever interface carries the default route. History is kept per network.

## Install

```bash
omarchy plugin add https://github.com/brodriro/doorman.git --enable
```

Or from a local checkout: `./install.sh --enable`.

Remove it from the bar with `omarchy plugin disable xaiovz.doorman`.

## Settings

Add keys to the widget's entry in `~/.config/omarchy/shell.json` (hot-reloaded), e.g. `{"id": "xaiovz.doorman", "notify": "new"}`.

| Key | Default | Meaning |
|---|---|---|
| `scanIntervalSec` | `60` | Seconds between scans (15–3600). |
| `absenceGraceSec` | `300` | A device must be missing this long to count as gone (phones sleep their Wi-Fi). |
| `activeSweep` | `true` | Ping every address of the local /24 each scan. `false` = only devices the computer already talks to. |
| `notify` | `"all"` | `all` = every join and leave, `new` = only devices never seen before, `off` = none. |

## How it works

`bin/doorman-scan` runs unprivileged: a ping sweep of your own /24 makes the kernel resolve every host's MAC, then the neighbor table (`ip neigh`) is read back; names come from mDNS (`avahi-browse`). Devices are identified by MAC, and the network by the gateway's MAC. The first scan of a network is a silent baseline, and a long gap between scans (suspend, another network) re-baselines silently instead of reporting everyone.

State lives in `~/.local/state/omarchy/doorman/<network>.json`, including any device you flag.

**Flagging is passive.** The plugin only observes the network; it never deauthenticates, disconnects, or otherwise attacks a device. Flagging a device marks it in the panel and offers to copy its MAC — the actual blocking is something you do yourself in the router's admin page (its MAC blocklist). If a flagged device returns with a new randomized MAC, change the Wi-Fi password.

**Network traffic:** with `activeSweep` on, every scan sends one ping to each address of the local /24 (up to 253 per minute by default). Turn it off on networks where that is unwelcome.

## Limitations

- Only the local subnet is visible. Devices behind another router (double NAT, a repeater in router mode) cannot be seen.
- Phones with private (randomized) MAC addresses are flagged as such; one may reappear as a "new" device when it rotates its address.
- A device that answers neither ARP nor mDNS while asleep shows as gone until it wakes.

## Requirements

`iproute2`, `iputils` (`ping`), `jq` — present on Omarchy. Optional: `avahi` (device names), NetworkManager (`nmcli`, Wi-Fi SSID), `wl-clipboard` (`wl-copy`, for the copy-MAC button).

## Development

```bash
tests/run.sh            # collector fixtures
node --test tests/      # presence logic
tests/harness.sh 30     # run the QML logic outside the shell against the live LAN
./install.sh            # copy into ~/.config/omarchy/plugins and reload
```

## License

MIT
