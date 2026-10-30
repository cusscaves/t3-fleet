# t3-fleet join (Windows 10/11) - sets up Windows AND Linux (Ubuntu 24.04 LTS in WSL2)
#   Open PowerShell and run:
#   irm https://raw.githubusercontent.com/cusscaves/t3-fleet/main/join/join.ps1 | iex
# Asks for the one-time invite code Cuss sends you privately. No secrets live in this file.
$ErrorActionPreference = 'Stop'
$Owner    = 'Cuss'
$PubKey   = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIsTdZEYwpO8dxsk6MtVjT5ZlJXlXSl+kecJ89LCqZdc your.email@example.com'
$ScriptUrl = 'https://raw.githubusercontent.com/cusscaves/t3-fleet/main/join/join.ps1'
$State    = "$env:ProgramData\t3-fleet"
$Self     = "$State\join.ps1"

function Say($m)  { Write-Host "`n$m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "`nStopped: $m" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
function Has-Winget { [bool](Get-Command winget -ErrorAction SilentlyContinue) }
function Winget($id) { winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null }

# --- run as administrator (re-launch a saved copy elevated) --------------------------------
$admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole('Administrators')
if (-not $admin) {
  $tmp = "$env:TEMP\t3-fleet-join.ps1"
  if ($PSCommandPath) { Copy-Item -LiteralPath $PSCommandPath $tmp -Force } else { Invoke-RestMethod $ScriptUrl -OutFile $tmp }
  Write-Host 'Windows will ask to allow changes - click Yes.'
  Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`""
  return
}

New-Item -ItemType Directory -Force $State | Out-Null
$resuming = Test-Path "$State\code"
Clear-Host
if (-not $resuming) {
  Write-Host @"
=====================================================================
  Lend this PC to $Owner's T3 Code  (Windows + Linux)
=====================================================================
This will:
  1. Install Tailscale (private network) and join $Owner's network.
     This PC can NOT reach $Owner's other machines.
  2. Turn on Windows' SSH server and let $Owner's key log in as you ($env:USERNAME).
  3. Install Node.js, Git, Claude Code and T3 Code (runs in the background).
  4. Add Linux: Ubuntu 24.04 LTS inside Windows (WSL2), set up the same way.
     Linux gets half the RAM on smaller PCs, more on big ones (Windows keeps 16 GB).
  5. Keep the PC awake while plugged in, so it stays reachable.
  (May ask for ONE restart - log back in, click Yes, and it continues.)

$Owner gets full use of this account and the Linux side (files, terminal,
AI coding agents) whenever this PC is on. Undo any time:
  right-click  $HOME\t3-fleet-leave.ps1  > Run with PowerShell
Details: https://github.com/cusscaves/t3-fleet/blob/main/docs/CONNECT.md
=====================================================================
"@
  if ((Read-Host 'Type yes to continue') -ne 'yes') { Fail 'cancelled, nothing changed.' }
  $code = (Read-Host "Paste the invite code from $Owner").Trim() -replace '^T3FLEET-', ''
  icacls $State /inheritance:r /grant 'Administrators:(OI)(CI)F' /grant 'SYSTEM:(OI)(CI)F' /grant "${env:USERNAME}:(OI)(CI)R" | Out-Null
  Set-Content -LiteralPath "$State\code" -Value $code
} else {
  Say 'Continuing setup after restart...'
  $code = (Get-Content -LiteralPath "$State\code" -Raw).Trim()
}
try {
  $raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($code.Replace('_','/').Replace('-','+')).PadRight([math]::Ceiling($code.Length/4)*4,'=')))
} catch { Remove-Item "$State\code" -Force; Fail "that invite code didn't work - ask $Owner for a new one" }
$TsName, $AuthKey, $Webhook = $raw.Split('|')
if (-not ($AuthKey -like 'tskey-auth-*')) { Remove-Item "$State\code" -Force; Fail "that invite code didn't work - ask $Owner for a new one" }

try {
  # --- 1. Tailscale ----------------------------------------------------------------------
  $TS = "$env:ProgramFiles\Tailscale\tailscale.exe"
  if (-not (Test-Path $TS)) {
    Say 'Installing Tailscale...'
    if (Has-Winget) { Winget 'Tailscale.Tailscale' }
    if (-not (Test-Path $TS)) {
      $msi = "$env:TEMP\tailscale.msi"
      Invoke-WebRequest 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $msi -UseBasicParsing
      Start-Process msiexec -Wait -ArgumentList "/i `"$msi`" /qn"
    }
    if (-not (Test-Path $TS)) { Fail 'Tailscale did not install' }
    Start-Sleep 5
  }
  & $TS status *> $null
  if ($LASTEXITCODE -ne 0) {
    Say "Joining $Owner's network as $TsName..."
    & $TS up --authkey=$AuthKey --hostname=$TsName --unattended
    if ($LASTEXITCODE -ne 0) { Fail "couldn't join (code used or expired? ask $Owner for a new one)" }
  }
  $TsIp = (& $TS ip -4 | Select-Object -First 1)

  # --- 2. SSH server ---------------------------------------------------------------------
  Say 'Turning on SSH...'
  if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null }
  Set-Service sshd -StartupType Automatic; Start-Service sshd
  if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True `
      -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
  }
  New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Force -PropertyType String `
    -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" | Out-Null
  $ak = "$env:ProgramData\ssh\administrators_authorized_keys"   # admin accounts read keys from here
  if (-not ((Test-Path $ak) -and (Select-String -LiteralPath $ak -SimpleMatch $PubKey -Quiet))) { Add-Content -LiteralPath $ak -Value $PubKey -Encoding ascii }
  icacls $ak /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

  # --- 3. Node, Git, Claude Code, T3 Code ------------------------------------------------
  Say 'Installing Node.js, Git, Claude Code and T3 Code...'
  Refresh-Path
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    if (Has-Winget) { Winget 'OpenJS.NodeJS.LTS'; Refresh-Path }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
      $msi = "$env:TEMP\node.msi"
      Invoke-WebRequest 'https://nodejs.org/dist/v22.20.0/node-v22.20.0-x64.msi' -OutFile $msi -UseBasicParsing
      Start-Process msiexec -Wait -ArgumentList "/i `"$msi`" /qn"; Refresh-Path
    }
  }
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'Node.js did not install' }
  if (-not (Get-Command git -ErrorAction SilentlyContinue) -and (Has-Winget)) { Winget 'Git.Git'; Refresh-Path }
  $npmPrefix = "$env:APPDATA\npm"
  & npm.cmd install -g --prefix $npmPrefix t3@latest @anthropic-ai/claude-code 2>&1 | Out-Null
  $t3 = "$npmPrefix\t3.cmd"
  if (-not (Test-Path $t3)) { Fail 'T3 Code did not install' }
  $up = [Environment]::GetEnvironmentVariable('Path','User')
  if ($up -notlike "*$npmPrefix*") { [Environment]::SetEnvironmentVariable('Path', "$up;$npmPrefix", 'User') }

  function Register-Bg($name, $exe, $arg) {
    $a = New-ScheduledTaskAction -Execute $exe -Argument $arg -WorkingDirectory $HOME
    $t = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME))
    $p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Limited
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
      -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $name -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName $name
  }
  Register-Bg 'T3 Code' 'cmd.exe' "/c `"`"$t3`" serve --host 127.0.0.1 >> `"$HOME\t3-serve.log`" 2>&1`""
  $ok = $false
  for ($i = 0; $i -lt 24 -and -not $ok; $i++) {
    Start-Sleep 5
    try { $ok = (Invoke-WebRequest 'http://127.0.0.1:3773/' -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch {}
  }
  & $TS serve --bg 3773 | Out-Null
  powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0

  # --- 4. Linux: WSL2 + Ubuntu 24.04 LTS, joined as <name>-linux -------------------------
  $Distro = 'Ubuntu-24.04'
  $LUser  = ($env:USERNAME.ToLower() -replace '[^a-z0-9_-]', ''); if (-not $LUser) { $LUser = 'friend' }
  if ($LUser -match '^[0-9]') { $LUser = "u$LUser" }
  function Distros { ((wsl.exe -l -q 2>$null) -join "`n") -replace "`0", '' -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } }

  if (-not (Test-Path "$State\linux-done")) {
    Say 'Setting up Linux (Ubuntu 24.04 LTS in WSL2)...'
    $wslCfg = "$HOME\.wslconfig"
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    if (-not (Test-Path $wslCfg)) {
      # 8-32 GB: half for Linux; bigger: everything but 16 GB (64 -> 48, 128 -> 112)
      $linGB = [math]::Max([math]::Floor($ramGB / 2), $ramGB - 16)
      Set-Content $wslCfg "[wsl2]`nmemory=${linGB}GB`n"
    }
    $vmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State
    $wsl = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
    if ($vmp -ne 'Enabled' -or $wsl -ne 'Enabled') {
      & wsl.exe --install --no-distribution
      Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -All | Out-Null
      Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -All | Out-Null
      Invoke-RestMethod $ScriptUrl -OutFile $Self
      Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'T3FleetJoin' `
        -Value "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Self`""
      Say 'Windows needs ONE restart to turn on Linux support.'
      Write-Host 'After you log back in, click Yes when asked - setup continues by itself.'
      if ((Read-Host 'Restart now? (yes/no)') -eq 'yes') { Restart-Computer -Force }
      return
    }
    & wsl.exe --update *> $null
    & wsl.exe --set-default-version 2 *> $null
    if ((Distros) -notcontains $Distro) {
      Say 'Downloading Ubuntu 24.04 LTS (a few minutes)...'
      & wsl.exe --install -d $Distro --no-launch --web-download
      if ((Distros) -notcontains $Distro) {
        $exe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\ubuntu2404.exe"
        if (Test-Path $exe) { & $exe install --root | Out-Null }
      }
      if ((Distros) -notcontains $Distro) { Fail 'Ubuntu did not install (restart, then run the command again)' }
    }
    $linux = @'
#!/bin/bash
set -euo pipefail
U='@@LUSER@@'; NAME='@@NAME@@-linux'; KEY='@@KEY@@'; PUB='@@PUB@@'; HOOK='@@HOOK@@'
if [ "${1:-1}" = 1 ]; then
  id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo "$U"
  echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-t3-owner; chmod 440 /etc/sudoers.d/90-t3-owner
  printf '[boot]\nsystemd=true\n[user]\ndefault=%s\n' "$U" > /etc/wsl.conf
  exit 0
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssh-server curl ca-certificates xz-utils git build-essential >/dev/null
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled ssh
tailscale status >/dev/null 2>&1 || tailscale up --authkey="$KEY" --hostname="$NAME" --operator="$U"
H=$(getent passwd "$U" | cut -d: -f6)
install -d -m 700 -o "$U" -g "$U" "$H/.ssh"
grep -qF "$PUB" "$H/.ssh/authorized_keys" 2>/dev/null || echo "$PUB" >> "$H/.ssh/authorized_keys"
chown "$U:$U" "$H/.ssh/authorized_keys"; chmod 600 "$H/.ssh/authorized_keys"
loginctl enable-linger "$U"
IP=$(tailscale ip -4 | head -1)
curl -fsS -m 15 -X POST -H 'Content-Type: application/json' \
  --data "{\"source\":\"fleet-join\",\"hostname\":\"$NAME\",\"ip\":\"$IP\",\"user\":\"$U\",\"os\":\"Linux (WSL2 Ubuntu 24.04)\"}" "$HOOK" >/dev/null || true
echo LINUX_READY
'@
    $linux = $linux.Replace('@@LUSER@@', $LUser).Replace('@@NAME@@', $TsName).Replace('@@KEY@@', $AuthKey).Replace('@@PUB@@', $PubKey).Replace('@@HOOK@@', $Webhook)
    $sh = "$State\linux-setup.sh"
    [IO.File]::WriteAllText($sh, ($linux -replace "`r`n", "`n"))
    $shWsl = '/mnt/c' + ($sh.Substring(2) -replace '\\', '/')
    & wsl.exe -d $Distro -u root -- bash $shWsl 1
    & wsl.exe --terminate $Distro | Out-Null
    Start-Sleep 3
    $out = & wsl.exe -d $Distro -u root -- bash $shWsl 2
    $out | Write-Host
    Remove-Item -LiteralPath $sh -Force
    if (-not ($out -match 'LINUX_READY')) { Fail 'Linux setup did not finish - run the command again' }
    Register-Bg 'T3 Linux keepalive' 'wsl.exe' "-d $Distro -u root -- sleep infinity"
    New-Item -ItemType File -Force "$State\linux-done" | Out-Null
  }

  # --- undo script -----------------------------------------------------------------------
  @"
# Removes $Owner's access from this PC. Right-click > Run with PowerShell (as administrator).
Unregister-ScheduledTask -TaskName 'T3 Code' -Confirm:`$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'T3 Linux keepalive' -Confirm:`$false -ErrorAction SilentlyContinue
`$ak = '$ak'
if (Test-Path `$ak) { (Get-Content `$ak) | Where-Object { `$_ -ne '$PubKey' } | Set-Content `$ak -Encoding ascii }
if ((Read-Host 'Also DELETE the Ubuntu Linux install and its files? (yes/no)') -eq 'yes') { wsl.exe --unregister $Distro }
else { wsl.exe -d $Distro -u root -- tailscale logout }
& '$TS' logout
Remove-Item -Recurse -Force '$State' -ErrorAction SilentlyContinue
Write-Host "Done: $Owner's key removed, T3 Code stopped, left the network."
"@ | Set-Content "$HOME\t3-fleet-leave.ps1" -Encoding utf8

  # --- 5. Tell the owner, clean up ------------------------------------------------------
  $body = @{ source = 'fleet-join'; hostname = $TsName; ip = "$TsIp"; user = $env:USERNAME; os = 'Windows'; t3 = "$ok" } | ConvertTo-Json -Compress
  try { Invoke-RestMethod -Method Post -Uri $Webhook -ContentType 'application/json' -Body $body -TimeoutSec 15 | Out-Null }
  catch { Write-Host "(couldn't notify - text ${Owner}: done, user $env:USERNAME)" }
  Remove-Item -LiteralPath "$State\code", $Self -Force -ErrorAction SilentlyContinue
  Say "All done! $Owner will finish remotely. Keep this PC on and plugged in."
} catch {
  Fail $_.Exception.Message
}
Read-Host 'Press Enter to close'
