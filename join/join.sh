#!/bin/bash
# t3-fleet join (macOS / Linux)
#   curl -fsSL https://raw.githubusercontent.com/cusscaves/t3-fleet/main/join/join.sh | bash
# Asks for the one-time invite code Cuss sends you privately. No secrets live in this file.
set -uo pipefail

OWNER='Cuss'
OWNER_PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIsTdZEYwpO8dxsk6MtVjT5ZlJXlXSl+kecJ89LCqZdc your.email@example.com'

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mStopped: %s\033[0m\n' "$*"; exit 1; }
ask()  { local a; read -rp "$1" a </dev/tty; printf '%s' "$a"; }

cat <<EOF

=====================================================================
  Lend this computer to ${OWNER}'s T3 Code
=====================================================================
This will:
  1. Install Tailscale (private network) and join ${OWNER}'s network.
     Your computer can NOT reach ${OWNER}'s other machines.
  2. Turn on SSH and let ${OWNER}'s key log in as you ($(whoami)).
  3. Tell ${OWNER} it's ready; ${OWNER} then installs T3 Code remotely.

${OWNER} gets full use of this account (files, terminal, AI coding agents)
whenever this computer is on. Undo any time:  bash ~/.t3-fleet-leave.sh
Full details: https://github.com/cusscaves/t3-fleet/blob/main/docs/CONNECT.md
=====================================================================
EOF
[ "$(ask 'Type yes to continue: ')" = yes ] || fail "cancelled, nothing changed."

CODE=$(ask "Paste the invite code from ${OWNER}: " | tr -d '[:space:]')
CODE=${CODE#T3FLEET-}
RAW=$(printf '%s' "$CODE" | tr '_-' '/+' | base64 -d 2>/dev/null || printf '%s' "$CODE" | tr '_-' '/+' | base64 -D 2>/dev/null)
IFS='|' read -r TS_NAME AUTHKEY WEBHOOK <<<"$RAW"
[[ "$AUTHKEY" == tskey-auth-* && -n "$TS_NAME" ]] || fail "that invite code didn't work - ask ${OWNER} for a new one"

OS=$(uname -s)
sudo -v || fail "need your password to install"

# --- 1. Tailscale --------------------------------------------------------------
if [ "$OS" = Darwin ]; then
  TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
  if [ ! -x "$TS" ]; then
    say "Installing Tailscale..."
    command -v brew >/dev/null && { brew install --cask tailscale-app 2>/dev/null || brew install --cask tailscale; }
    if [ ! -x "$TS" ]; then
      open "https://tailscale.com/download/mac"
      ask "Install Tailscale from the page that opened, open it once, then press Enter. " >/dev/null
    fi
    [ -x "$TS" ] || fail "Tailscale app not found in /Applications"
  fi
  open -ga Tailscale; sleep 5
else
  TS=tailscale
  if ! command -v tailscale >/dev/null; then
    say "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh || fail "Tailscale install failed"
  fi
  sudo systemctl enable --now tailscaled >/dev/null 2>&1 || true
fi
if ! "$TS" status >/dev/null 2>&1; then
  say "Joining ${OWNER}'s network as ${TS_NAME}..."
  UP=(up --authkey="$AUTHKEY" --hostname="$TS_NAME")
  [ "$OS" = Darwin ] || UP+=(--operator="$(whoami)")
  sudo "$TS" "${UP[@]}" || fail "couldn't join (code used or expired? ask ${OWNER} for a new one)"
fi
TS_IP=$("$TS" ip -4 2>/dev/null | head -1)

# --- 2. SSH -----------------------------------------------------------------------
say "Turning on SSH..."
if [ "$OS" = Darwin ]; then
  sudo systemsetup -setremotelogin on >/dev/null 2>&1 \
    || sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null \
    || echo "If asked: System Settings > General > Sharing > Remote Login = On"
else
  if ! command -v sshd >/dev/null && [ ! -x /usr/sbin/sshd ]; then
    if command -v apt-get >/dev/null; then sudo apt-get install -y openssh-server
    elif command -v dnf >/dev/null; then sudo dnf install -y openssh-server
    elif command -v pacman >/dev/null; then sudo pacman -S --noconfirm openssh; fi
  fi
  sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null || true
  sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true
fi
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qF "$OWNER_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$OWNER_PUBKEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

cat > ~/.t3-fleet-leave.sh <<LEAVE
#!/bin/bash
# Removes ${OWNER}'s access from this computer.
grep -vF '$OWNER_PUBKEY' ~/.ssh/authorized_keys > ~/.ssh/ak.tmp; mv ~/.ssh/ak.tmp ~/.ssh/authorized_keys
systemctl --user disable --now t3code.service t3-heal.timer 2>/dev/null
launchctl list 2>/dev/null | awk '/t3/{print \$3}' | xargs -I{} launchctl remove {} 2>/dev/null
sudo "$TS" logout
echo "Done: ${OWNER}'s key removed, T3 stopped, left the network."
LEAVE
chmod +x ~/.t3-fleet-leave.sh

# --- 3. Tell the owner ----------------------------------------------------------
curl -fsS -m 15 -X POST -H 'Content-Type: application/json' \
  --data "{\"source\":\"fleet-join\",\"hostname\":\"$TS_NAME\",\"ip\":\"$TS_IP\",\"user\":\"$(whoami)\",\"os\":\"$OS\"}" \
  "$WEBHOOK" >/dev/null 2>&1 || echo "(couldn't notify - text ${OWNER}: done, user $(whoami))"
say "All done! ${OWNER} will finish setup remotely. Keep this computer on and plugged in."
