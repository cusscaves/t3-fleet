# Owner guide (Cuss)

## One-time Tailscale settings

[Access controls](https://login.tailscale.com/admin/acls): friends' machines are tagged and can't
start connections to anything. Your own devices (members) reach everything.

```jsonc
"tagOwners": { "tag:friend": ["autogroup:admin"] },
// replace the default allow-all rule ({"src": ["*"], ...}) with:
"acls": [ { "action": "accept", "src": ["autogroup:member"], "dst": ["*:*"] } ],
```

Also: [DNS](https://login.tailscale.com/admin/dns) > MagicDNS + HTTPS Certificates on (needed for
`https://<machine>.<tailnet>.ts.net`), and disable key expiry on Linny and the Mac.

## Inviting someone

```bash
owner/make-invite jake-pc        # paste a reusable, pre-approved, tag:friend, 1-day key
```

Send the repo link + code privately. When they finish, the "Fleet: friend machine joined" webhook
wakes the t3-setup thread, which runs `owner/onboard-machine <name> <user>`:
Node v22 (user-local), `t3 service install`, `t3-heal` timer, `tailscale serve`, Claude CLI, ssh
alias, fleet-watch lines on Mac + Linny, and a 30-minute T3 pairing link (show as QR with
`qrencode`). A Windows PC shows up twice: `<name>` (Windows) and `<name>-linux` (Ubuntu in WSL2).

## Monitoring

`fleet-watch/` runs every 5 min on the Mac (launchd) and Linny (systemd timer). Alerts go to the
t3-setup T3 thread (queued while the Mac sleeps) and Mac notifications. Details:
[fleet-watch/README.md](../fleet-watch/README.md). Update Linny's copy: `fleet-watch/deploy-linny.sh`.

| Role | Alerts when |
|--|--|
| self / server / box | unreachable, SSH or T3 broken, key or T3 login expiring |
| laptop | online but T3 broken (sleeping is normal) |
| phone | never |

## Pairing a device to Linny's T3

```bash
ssh linny '~/.t3/runtime/versions/*/t3 pair --tailscale --label "iPhone" --ttl 15m'
```

Logins last 30 days; fleet-watch on Linny warns 7 days before any expires.

## Local-only files (never committed)

| File | Holds |
|--|--|
| `~/.config/fleet-watch/env` | fleet alert webhook URL (+ `FLEET_WATCH_WEBHOOK_SELF_ONLY=1` on the Mac) |
| `~/.config/fleet-watch/join-webhook` | join webhook URL (inside every invite code) |
| `owner/issued.log` | who you invited, when |
