# Connecting with Cuss, safely

Two directions. The defaults are built so a mistake costs little.

## If you're lending a computer

**What Cuss will ask you for**
- What it runs (Mac / Windows / Linux) and a short name for it (e.g. `jake-pc`).
- That it can stay on and plugged in (8 GB RAM or more is plenty).
- That you're OK with the access below.

**What you get from Cuss**
- A link to this repo and a **one-time invite code**, sent privately. It expires in about a day.

**What Cuss can do on your computer once joined**
- Log in as *your* user account over SSH, read/write your files, run programs, and run AI
  coding agents (T3 Code, Claude Code) there. On Windows, also a separate Ubuntu Linux install.
- Treat it like your own account was handed over. If there's something private on it, use a
  separate user account or a spare machine.

**What Cuss can NOT do**
- Your computer joins Cuss's network *tagged* `tag:friend`. Tailscale's rules stop it from reaching
  any of Cuss's machines, and stop other friends' machines from reaching yours.
- Nothing sees your other devices, your home network, or your Tailscale account (you don't need one).

**Never give anyone (including Cuss)**
- Your computer password, Apple ID / Microsoft / Google login, or 2FA codes.
- Private keys (`id_ed25519`, `id_rsa`), API keys, password-manager exports.
- Remote-desktop sessions (AnyDesk/TeamViewer) to "help set it up". The installer does it.

**Stopping**
- Run the leave script any time: `bash ~/.t3-fleet-leave.sh` (Mac/Linux) or right-click
  `t3-fleet-leave.ps1` in your home folder > Run with PowerShell (Windows). It removes Cuss's key,
  stops T3 Code, and leaves the network. Tell Cuss and he'll remove it on his side too.

## If you're connecting someone (Cuss's checklist)

1. Ask: OS, a name, "can it stay on?", and get an explicit yes to the access above.
2. Make a Tailscale key (reusable, pre-approved, `tag:friend`, 1-day expiry) and run
   `owner/make-invite <name>`. Send the link + code **privately**. Never paste a code in a group chat.
3. When the join webhook fires, the T3 agent runs `owner/onboard-machine` and gives you a pairing QR.
4. On their machine: `claude auth login` once (agents need a login there).
5. Off-boarding: remove the machine in the Tailscale admin console and its lines in
   `fleet-watch/fleet*.conf`; `t3 auth session list/revoke` for any pairing.

## Likewise: if a friend wants to use one of Cuss's machines

Off by default. Joining Cuss's fleet never gives anyone access to Cuss's machines. If you decide
to share, do it by hand, limited and revocable:

- **Network**: use Tailscale *machine sharing* (admin console > the machine > Share). They accept it
  in their own Tailscale account. Never add them to your tailnet, and never send them an auth key.
- **T3 Code**: give a short-lived, limited pairing, not a full one:
  `t3 pair --tailscale --ttl 15m --label <friend> --scope orchestration:read --scope orchestration:operate`
  (they can run agents, can't change settings, keys or providers). Remember: their agent runs use
  **your** Claude/Codex subscriptions.
- **Revoke**: `t3 auth session list` then `t3 auth session revoke <id>`, and un-share the machine.
- **Never share**: your Tailscale login, auth keys, SSH private keys, API keys, or `~/.config`.
