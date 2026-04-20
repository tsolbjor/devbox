# =========================
# PARAMETERS (edit these)
# =========================

$Config = @{
  UpdateWindowsOS    = $true   # PSWindowsUpdate — installs OS updates, no auto-reboot
  UpdateDefender     = $true   # Update-MpSignature — Windows Defender definitions
  UpdateStoreApps    = $true   # trigger Microsoft Store "update all" (runs in background)
  UpdateWSL          = $true   # wsl --update — WSL kernel/runtime
  UpdatePSModules    = $true   # Update-Module — all installed PowerShell modules
  WingetUpgradeAll   = $true   # winget upgrade --all
  UpdateNpmGlobals   = $true   # ncu -g if npm and ncu are available
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
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
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
  $obj = Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" `
    -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01"
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

if ($Config.UpdateWindowsOS) {
  Show-Progress "Installing Windows Updates"
  Update-WindowsOS
}

if ($Config.UpdateDefender) {
  Show-Progress "Updating Defender definitions"
  Update-Defender
}

if ($Config.UpdateStoreApps) {
  Show-Progress "Triggering Microsoft Store updates"
  Update-StoreApps
}

if ($Config.UpdateWSL) {
  Show-Progress "Updating WSL"
  Update-WSL
}

if ($Config.UpdatePSModules) {
  Show-Progress "Updating PowerShell modules"
  Update-PSModules
}

if ($Config.WingetUpgradeAll) {
  Show-Progress "Upgrading all winget packages"
  Update-WingetAll
}

if ($Config.UpdateNpmGlobals) {
  Show-Progress "Updating global npm packages"
  Update-NpmGlobals
}

Write-Progress -Activity "devbox update" -Completed
Show-Progress "Done"
Write-Host "All updates complete." -ForegroundColor Green
