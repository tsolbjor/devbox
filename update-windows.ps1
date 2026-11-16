# =========================
# PARAMETERS (edit these)
# =========================

$Config = @{
  UpdateWindowsOS    = $true   # PSWindowsUpdate — installs OS updates, no auto-reboot
  UpdateDefender     = $true   # Update-MpSignature — Windows Defender definitions
  UpdateStoreApps    = $true   # trigger Microsoft Store "update all" (runs in background)
  UpdateWSL          = $true   # wsl --update — WSL kernel/runtime
  UpdatePSModules    = $false  # Update-Module — all installed PowerShell modules (slow, low payoff)
  WingetUpgradeAll   = $true   # winget upgrade --all
  UpdateNode         = $true   # latest patch of the fnm default Node major (fnm itself rides winget)
  UpdateNpmGlobals   = $true   # npm update -g (in-range updates) if npm is available
}

# =========================
# IMPLEMENTATION
# =========================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# A console this process has to itself (sudo in "new window" mode, a double-click,
# Run as administrator) closes the moment the script exits, taking the summary and
# any error with it. Rerun the script inside this one and wait for a key before
# closing. In an existing terminal other processes share the console, so nothing
# changes; with no console at all (CI, a scheduled task) the count is 0.
function Test-ConsoleClosesOnExit {
  if (-not [Environment]::UserInteractive) { return $false }
  try {
    Add-Type -Namespace Devbox -Name ConsoleInfo -MemberDefinition `
      '[DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList(uint[] list, uint count);'
    return [Devbox.ConsoleInfo]::GetConsoleProcessList((New-Object UInt32[] 16), 16) -eq 1
  } catch { return $false }
}

if ($PSCommandPath -and -not $env:DEVBOX_NO_PAUSE -and (Test-ConsoleClosesOnExit)) {
  $env:DEVBOX_NO_PAUSE = "1"
  $exitCode = 0
  try {
    & $PSCommandPath @args
    if ($LASTEXITCODE) { $exitCode = $LASTEXITCODE }
  } catch {
    Write-Host "`n⚠ $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
  }
  Write-Host "`nPress Enter to close this window..." -ForegroundColor Cyan -NoNewline
  [void](Read-Host)
  exit $exitCode
}

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    throw "Please run this script as Administrator."
  }
}

function Test-Command($Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-WindowsOS {
  if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "→ Installing PSWindowsUpdate module" -ForegroundColor Cyan
    # Windows PowerShell 5.1 defaults to TLS 1.0, which PSGallery rejects; and a
    # fresh box has no NuGet provider and an untrusted gallery — all of which turn
    # into prompts or hard failures. Handle them non-interactively.
    [Net.ServicePointManager]::SecurityProtocol =
      [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -Confirm:$false -AllowClobber
  }
  Import-Module PSWindowsUpdate
  Write-Host "→ Installing Windows Updates" -ForegroundColor Cyan
  $results = Install-WindowsUpdate -AcceptAll -AutoReboot:$false -IgnoreReboot
  if ($results) {
    $needsReboot = $results | Where-Object { $_.RebootRequired }
    if ($needsReboot) {
      Write-Host "⚠ Updates installed — reboot required to finish." -ForegroundColor Yellow
    } else {
      Write-Host "✓ Windows Updates installed" -ForegroundColor Green
    }
  } else {
    Write-Host "✓ Windows is up to date" -ForegroundColor Green
  }
}

function Update-Defender {
  Write-Host "→ Updating Windows Defender definitions" -ForegroundColor Cyan
  Update-MpSignature
  Write-Host "✓ Defender definitions up to date" -ForegroundColor Green
}

function Update-WSL {
  Write-Host "→ Updating WSL" -ForegroundColor Cyan
  wsl --update
  Write-Host "✓ WSL up to date" -ForegroundColor Green
}

function Update-PSModules {
  Write-Host "→ Updating PowerShell modules" -ForegroundColor Cyan
  Update-Module -Force
  Write-Host "✓ PowerShell modules up to date" -ForegroundColor Green
}

function Update-StoreApps {
  Write-Host "→ Triggering Microsoft Store update scan" -ForegroundColor Cyan
  # The MDM app-management class is absent on some Windows editions/configs;
  # treat that as a graceful skip rather than a run-ending error.
  try {
    $obj = Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" `
      -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction Stop
  } catch {
    Write-Warning "Store update scan unavailable on this Windows edition/config. Skipping."
    return
  }
  Invoke-CimMethod -InputObject $obj -MethodName UpdateScanMethod | Out-Null
  Write-Host "✓ Store update scan triggered (updates install in background)" -ForegroundColor Green
}

function Ensure-Winget {
  if (-not (Test-Command "winget")) {
    throw "winget is not available. Install 'App Installer' from Microsoft Store, then rerun."
  }
}

# Run a native command, echoing its output live while keeping it for inspection.
# stderr merges into the stream as text: under "Stop", Windows PowerShell 5.1
# turns the first stderr line of a 2>&1 into a terminating error.
function Invoke-NativeCaptured {
  param([Parameter(Mandatory=$true)][scriptblock]$Command)
  $ErrorActionPreference = "Continue"
  $lines = New-Object System.Collections.Generic.List[string]
  & $Command 2>&1 | ForEach-Object {
    $line = "$_"
    $lines.Add($line)
    Write-Host $line
  }
  return ,$lines.ToArray()
}

function Update-WingetAll {
  Write-Host "→ Running winget upgrade --all" -ForegroundColor Cyan
  $out = Invoke-NativeCaptured { winget upgrade --all --accept-package-agreements --accept-source-agreements }
  $exit = $LASTEXITCODE
  # winget will not upgrade a per-user install from an elevated session, and this
  # script must run elevated. It says so after the package's "(n/m) Found <name>
  # [<id>]" line; pair the two so the warning can name what to rerun.
  $userScope = @()
  $id = $null
  foreach ($line in $out) {
    if ($line -match '^\(\d+/\d+\) Found .* \[(?<id>[^\]]+)\]') { $id = $Matches.id }
    elseif ($id -and $line -match 'installed for user scope cannot be') { $userScope += $id; $id = $null }
  }
  if ($userScope) {
    Write-Host "⚠ winget skipped $($userScope.Count) per-user install(s), which it cannot upgrade elevated." -ForegroundColor Yellow
    Write-Host "  From a terminal that is not elevated, run:" -ForegroundColor Yellow
    foreach ($u in $userScope) { Write-Host "    winget upgrade --id $u -e" -ForegroundColor Yellow }
  } elseif ($exit -ne 0 -and $exit -ne -1978335189) {   # 0x8A15002B: no applicable upgrade
    throw ("winget upgrade --all failed (exit 0x{0:X8})" -f $exit)
  } else {
    Write-Host "✓ winget upgrade complete" -ForegroundColor Green
  }
}

# Put fnm and its default Node on PATH for this session (see Ensure-Node in setup).
function Enable-Fnm {
  if (-not (Test-Command "fnm")) { return $false }
  fnm env --shell powershell | Out-String | Invoke-Expression
  return $true
}

# The newest patch of the default major. The replaced patch is uninstalled: it was
# only ever the default, and projects asking for the major resolve to the new one.
# Majors never move here — change NodeMajorVersion in setup-windows.ps1 for that.
function Update-Node {
  if (-not (Enable-Fnm)) {
    Write-Host "✓ fnm not installed, skipping" -ForegroundColor Green
    return
  }
  $current = @(fnm list) | ForEach-Object { if ($_ -match '(v\d+\.\d+\.\d+).*\bdefault\b') { $Matches[1] } } | Select-Object -First 1
  if (-not $current) {
    Write-Host "✓ no fnm default set, skipping" -ForegroundColor Green
    return
  }
  $major = ($current.TrimStart('v') -split '\.')[0]
  $latest = @(fnm ls-remote) | ForEach-Object { if ($_ -match "^(v$major\.\d+\.\d+)") { $Matches[1] } } | Select-Object -Last 1
  if (-not $latest -or $latest -eq $current) {
    Write-Host "✓ node $current is the latest $major.x" -ForegroundColor Green
    return
  }
  Write-Host "→ Updating node $current → $latest" -ForegroundColor Cyan
  fnm install $latest
  if ($LASTEXITCODE -ne 0) { throw "fnm install $latest failed (exit $LASTEXITCODE)" }
  fnm default $latest
  if ($LASTEXITCODE -ne 0) { throw "fnm default $latest failed (exit $LASTEXITCODE)" }
  Write-Host "✓ node now $latest (fnm default)" -ForegroundColor Green
  # Fails with "Access is denied" while a node.exe from it still runs (an editor's
  # language server, a dev server); the new default is in place either way.
  fnm uninstall $current
  if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠ could not remove node $current (still in use?) — close what runs it, then: fnm uninstall $current" -ForegroundColor Yellow
  }
}

function Update-NpmGlobals {
  [void](Enable-Fnm)
  if (-not (Test-Command "npm")) {
    Write-Host "✓ npm not found, skipping global npm package updates." -ForegroundColor Green
    return
  }
  Write-Host "→ Updating global npm packages" -ForegroundColor Cyan
  $out = Invoke-NativeCaptured { npm update -g }
  if ($LASTEXITCODE -ne 0) { throw "npm update -g failed (exit $LASTEXITCODE)" }
  # npm runs no install script it has not been told to allow (allow-scripts), and
  # only warns. A package whose postinstall fetches its binary (azure-functions-
  # core-tools, esbuild) then keeps the old one or none. Allowing them is a trust
  # decision about third-party code, so name them rather than allow them here.
  $skipped = @($out | ForEach-Object {
    if ($_ -match '^npm warn install-scripts\s+(?<pkg>(@[^/\s]+/)?[^@\s]+)@\S+ \(') { $Matches.pkg }
  } | Select-Object -Unique)
  if ($skipped) {
    # The globals that pull them in — the packages a reinstall has to name.
    $tops = @()
    try {
      $ErrorActionPreference = "Continue"
      $tree = (npm ls -g --json @skipped 2>$null) | Out-String | ConvertFrom-Json
      if ($tree.PSObject.Properties['dependencies']) { $tops = @($tree.dependencies.PSObject.Properties.Name) }
    } catch { }
    finally { $ErrorActionPreference = "Stop" }
    if (-not $tops) { $tops = $skipped }
    Write-Host "⚠ npm skipped the install scripts of: $($skipped -join ', ')" -ForegroundColor Yellow
    Write-Host "  Globals that use them may be incomplete. To allow the scripts once and reinstall:" -ForegroundColor Yellow
    Write-Host "    npm install -g --allow-scripts=$($skipped -join ',') $($tops -join ' ')" -ForegroundColor Yellow
    Write-Host "  or allow them for every global install: npm config set allow-scripts=$($skipped -join ',') --location=user" -ForegroundColor Yellow
  } else {
    Write-Host "✓ global npm packages up to date" -ForegroundColor Green
  }
}

$script:currentStep = 0
$script:totalSteps  = 0

# No Write-Progress: its bar stays up while winget/npm write, and when their
# output scrolls the window the bar puts back the stale text it drew over.
function Show-Progress {
  param([Parameter(Mandatory=$true)][string]$Status)
  $script:currentStep++
  Write-Host "`n[$($script:currentStep)/$($script:totalSteps)] $Status" -ForegroundColor White
}

$script:failures = @()

# Run one update step; a failure is reported and recorded, then the run continues
# to the next step instead of aborting. Mirrors update-ubuntu.sh's run_step.
function Invoke-Step {
  param(
    [Parameter(Mandatory=$true)][string]$Status,
    [Parameter(Mandatory=$true)][scriptblock]$Action
  )
  Show-Progress $Status
  try {
    & $Action
  } catch {
    Write-Warning "Step failed: $Status — $($_.Exception.Message)"
    $script:failures += $Status
  }
}

# =========================
# RUN
# =========================

Assert-Admin
Ensure-Winget

$totalSteps = 1  # always: Done
if ($Config.UpdateWindowsOS)  { $totalSteps++ }
if ($Config.UpdateDefender)   { $totalSteps++ }
if ($Config.UpdateStoreApps)  { $totalSteps++ }
if ($Config.UpdateWSL)        { $totalSteps++ }
if ($Config.UpdatePSModules)  { $totalSteps++ }
if ($Config.WingetUpgradeAll) { $totalSteps++ }
if ($Config.UpdateNode)       { $totalSteps++ }
if ($Config.UpdateNpmGlobals) { $totalSteps++ }
$script:totalSteps = $totalSteps

if ($Config.UpdateWindowsOS)  { Invoke-Step "Installing Windows Updates"       { Update-WindowsOS } }
if ($Config.UpdateDefender)   { Invoke-Step "Updating Defender definitions"    { Update-Defender } }
if ($Config.UpdateStoreApps)  { Invoke-Step "Triggering Microsoft Store updates" { Update-StoreApps } }
if ($Config.UpdateWSL)        { Invoke-Step "Updating WSL"                      { Update-WSL } }
if ($Config.UpdatePSModules)  { Invoke-Step "Updating PowerShell modules"      { Update-PSModules } }
if ($Config.WingetUpgradeAll) { Invoke-Step "Upgrading all winget packages"    { Update-WingetAll } }
# After winget: that is what updates fnm itself.
if ($Config.UpdateNode)       { Invoke-Step "Updating Node (fnm)"              { Update-Node } }
if ($Config.UpdateNpmGlobals) { Invoke-Step "Updating global npm packages"     { Update-NpmGlobals } }

Show-Progress "Done"
if ($script:failures.Count -gt 0) {
  Write-Host "`nCompleted with failures in $($script:failures.Count) step(s):" -ForegroundColor Yellow
  $script:failures | ForEach-Object { Write-Host "  ⚠ $_" -ForegroundColor Yellow }
  exit 1
} else {
  Write-Host "All updates complete." -ForegroundColor Green
}
