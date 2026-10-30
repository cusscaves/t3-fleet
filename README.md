<img src="assets/icon.svg" width="64" height="64" alt="">

# t3-fleet

Cuss's personal compute fleet for [T3 Code](https://t3.codes): every machine on a private
[Tailscale](https://tailscale.com) network, running T3 Code, watched around the clock and
self-healing. Friends can lend a spare computer in about five minutes.

| Machine | Role |
|--|--|
| MacBook Air | daily driver, T3 desktop app |
| Linny (Ubuntu) | always-on server: T3 Code, fleet watcher, file shares |
| iPhone | T3 on the go (paired to Linny) |
| Friends' computers | lent machines, isolated from everything else |

---

## Join

**Lending Cuss a computer?** Mac, Windows or Linux, 8 to 128 GB RAM.
Read [what you're agreeing to](docs/CONNECT.md#if-youre-lending-a-computer) first (2 minutes).
Prefer a friendly version? [Google Doc: Lend Cuss a computer](https://docs.google.com/document/d/1fh6q6QeG0WPY0TOQu4f9Ce5M67Fyj6ulQxyY9vzFZWE/edit?usp=sharing)
You need the **invite code** Cuss sent you privately.

**Windows** (sets up Windows *and* Ubuntu Linux): click Start, type `PowerShell`, open it, paste:

```powershell
irm https://raw.githubusercontent.com/cusscaves/t3-fleet/main/join/join.ps1 | iex
```

**Mac or Linux**: open Terminal, paste:

```bash
curl -fsSL https://raw.githubusercontent.com/cusscaves/t3-fleet/main/join/join.sh | bash
```

Type `yes`, paste your code, enter your computer password once. That's it: Cuss finishes the rest
remotely. Undo any time with the leave script it creates (`~/.t3-fleet-leave.sh`, or
`t3-fleet-leave.ps1` in your home folder on Windows).

---

## What's in here

| Path | What |
|--|--|
| [`join/`](join) | Public installers (no secrets). Ask for a one-time invite code. |
| [`owner/`](owner) | Cuss's tools: `make-invite` (one-time codes), `onboard-machine` (finish setup over SSH). |
| [`fleet-watch/`](fleet-watch) | Monitoring + safe auto-repair for every machine; runs on the Mac and Linny. |
| [`docs/CONNECT.md`](docs/CONNECT.md) | Connecting safely, both directions: what to ask for, what never to share. |
| [`docs/OWNER.md`](docs/OWNER.md) | How the fleet is set up, one-time Tailscale settings, day-to-day commands. |

## How a join works

```
friend runs join  ──>  Tailscale (tag:friend, can't reach Cuss's machines)
                  ──>  SSH on, Cuss's public key added, undo script written
                  ──>  pings Cuss's T3 thread ("fleet-join")
Cuss's agent      ──>  owner/onboard-machine over SSH: Node, T3 Code service, self-heal,
                       tailscale serve, fleet-watch entry, T3 pairing QR
```

Nothing secret is in this repo. The invite code (Tailscale auth key + notify URL) is the only
sensitive piece; it's sent privately and expires in a day.
