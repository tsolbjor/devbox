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
  UpdateNpmGlobals   = $true   # npm update -g (in-range updates) if npm is available
}

# =========================
# IMPLEMENTATION
# =========================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Update-WingetAll {
  Write-Host "→ Running winget upgrade --all" -ForegroundColor Cyan
  winget upgrade --all --accept-package-agreements --accept-source-agreements
  Write-Host "✓ winget upgrade complete" -ForegroundColor Green
}

function Update-NpmGlobals {
  if (-not (Test-Command "npm")) {
    Write-Host "✓ npm not found, skipping global npm package updates." -ForegroundColor Green
    return
  }
  Write-Host "→ Updating global npm packages" -ForegroundColor Cyan
  npm update -g
  Write-Host "✓ global npm packages up to date" -ForegroundColor Green
}

$script:currentStep = 0
$script:totalSteps  = 0

function Show-Progress {
  param([Parameter(Mandatory=$true)][string]$Status)
  $script:currentStep++
  $pct = [int]($script:currentStep / $script:totalSteps * 100)
  Write-Progress -Activity "devbox update" -Status "[$($script:currentStep)/$($script:totalSteps)] $Status" -PercentComplete $pct
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
if ($Config.UpdateNpmGlobals) { $totalSteps++ }
$script:totalSteps = $totalSteps

if ($Config.UpdateWindowsOS)  { Invoke-Step "Installing Windows Updates"       { Update-WindowsOS } }
if ($Config.UpdateDefender)   { Invoke-Step "Updating Defender definitions"    { Update-Defender } }
if ($Config.UpdateStoreApps)  { Invoke-Step "Triggering Microsoft Store updates" { Update-StoreApps } }
if ($Config.UpdateWSL)        { Invoke-Step "Updating WSL"                      { Update-WSL } }
if ($Config.UpdatePSModules)  { Invoke-Step "Updating PowerShell modules"      { Update-PSModules } }
if ($Config.WingetUpgradeAll) { Invoke-Step "Upgrading all winget packages"    { Update-WingetAll } }
if ($Config.UpdateNpmGlobals) { Invoke-Step "Updating global npm packages"     { Update-NpmGlobals } }

Write-Progress -Activity "devbox update" -Completed
Show-Progress "Done"
if ($script:failures.Count -gt 0) {
  Write-Host "`nCompleted with failures in $($script:failures.Count) step(s):" -ForegroundColor Yellow
  $script:failures | ForEach-Object { Write-Host "  ⚠ $_" -ForegroundColor Yellow }
  exit 1
} else {
  Write-Host "All updates complete." -ForegroundColor Green
}
