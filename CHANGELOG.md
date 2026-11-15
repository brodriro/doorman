# Changelog

All notable changes to Doorman are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[semantic versioning](https://semver.org/).

## [0.2.0] - 2026-11-15

### Added
- **Flag intruders**: mark a device you don't recognize; it moves to a
  **Flagged** alert section where you can copy its MAC to paste into the
  router's own blocklist. The flag is passive (the plugin never disconnects or
  attacks a device) and persists across scans.
- Panel redesign coordinated with the Figma proposals: hero icon tile, counter
  chips (online / new / absent), per-device type icon, state badges, uppercase
  section headers with counts, and a scan-cadence footer. All colours come from
  live theme roles, so it follows the Omarchy theme.

### Fixed
- The collector now resolves the gateway's MAC even in passive (`--no-sweep`)
  mode, so a scan is no longer discarded for a null network id after boot or
  suspend.
- Notifications now show "Doorman" as the app name (was lowercase).

## [0.1.0]

### Added
- Bar widget with a live count of other devices online, lighting up when a
  never-seen device joins.
- Panel listing devices online and seen before, recent activity, and per-device
  renaming.
- Desktop notifications for joins and leaves (configurable), with one summary
  when many change at once.
- Unprivileged collector (ping sweep + `ip neigh`, mDNS names); per-network
  presence state with silent baselining and an absence grace period.
