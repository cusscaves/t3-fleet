# fleet-watch

Keeps every Tailscale machine reachable over SSH and T3 Code. Two watchers, every 5 min:

- **Mac**: launchd `com.cuss.fleet-watch` -> `~/bin/fleet-watch` (symlink to this file), config
  `fleet.conf`. Desktop notifications for everything; webhook only for its own problems
  (`FLEET_WATCH_WEBHOOK_SELF_ONLY=1`). Pauses while the Mac sleeps.
- **Linny** (always on): systemd user `fleet-watch.timer` -> `~/.local/bin/fleet-watch`, config
  `fleet.linny.conf`, state/log in `~/.local/state/fleet-watch/`. Sends the fleet webhook alerts.
  Update it with `./deploy-linny.sh`.

Roles: `self`/`server`/`box` alert when unreachable; `laptop` alerts only when online but broken;
`phone` never alerts. A machine must fail 2 runs in a row before alerting; recoveries report at once.

- Machines are discovered from `tailscale status --json`; roles/checks live in `fleet.conf`.
- Checks: Tailscale reachability, SSH login, T3 Code HTTP 200, node key expiry (< 14 days).
- Safe repairs (max once per 15 min per machine): restart `t3code.service` + `tailscale serve`
  over SSH, reopen T3 Code / Tailscale on the Mac. **Never power-cycles anything.**
- Alerts: macOS notification on each state change, repeated every 6 h while broken.
  Each alert also POSTs to the T3 webhook in `~/.config/fleet-watch/env`, which wakes the
  fleet-keeper agent in the t3-setup thread to diagnose and report.
- Linny additionally heals itself every 2 min (`t3-heal.timer`, on Linny).

Commands: `fleet-watch --status` (last report) · `fleet-watch --dry-run` (check, no repairs/alerts)
Files: `~/.local/state/fleet-watch/{state.json,STATUS.md}` · `~/Library/Logs/fleet-watch.log`
Add a machine: add a line to `fleet.conf` (it will alert as "unconfigured" until you do).
