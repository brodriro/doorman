# Doorman

An [Omarchy](https://omarchy.org) shell plugin that watches the local network you are on and tells you who joins and who leaves.

- **Bar icon** with the number of other devices online; it lights up (`3 +1`) when a device never seen before joins, until you open the panel. Right-click scans immediately.
- **Panel**: the network (SSID or "Wired network", subnet, last scan), devices online, devices seen before, and recent activity. Click the pencil on a device to give it a name.
- **Notifications** for joins and leaves (configurable), one summary when many change at once.
- Works on Wi-Fi and wired connections; it follows whatever interface carries the default route. History is kept per network.

## Install

```bash
omarchy plugin add <git-url-of-this-repo> --enable
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

State lives in `~/.local/state/omarchy/doorman/<network>.json`.

**Network traffic:** with `activeSweep` on, every scan sends one ping to each address of the local /24 (up to 253 per minute by default). Turn it off on networks where that is unwelcome.

## Limitations

- Only the local subnet is visible. Devices behind another router (double NAT, a repeater in router mode) cannot be seen.
- Phones with private (randomized) MAC addresses are flagged as such; one may reappear as a "new" device when it rotates its address.
- A device that answers neither ARP nor mDNS while asleep shows as gone until it wakes.

## Requirements

`iproute2`, `iputils` (`ping`), `jq` — present on Omarchy. Optional: `avahi` (device names), NetworkManager (`nmcli`, Wi-Fi SSID).

## Development

```bash
tests/run.sh            # collector fixtures
node --test tests/      # presence logic
tests/harness.sh 30     # run the QML logic outside the shell against the live LAN
./install.sh            # copy into ~/.config/omarchy/plugins and reload
```

## License

MIT
