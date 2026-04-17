# =========================
# PARAMETERS (edit these)
# =========================

$Config = @{
  WingetUpgradeAll = $true   # winget upgrade --all
  UpdateNpmGlobals = $true   # ncu -g if npm and ncu are available
}

# =========================
# IMPLEMENTATION
# =========================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-Command($Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
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

Ensure-Winget

$totalSteps = 1  # always: Done
if ($Config.WingetUpgradeAll) { $totalSteps++ }
if ($Config.UpdateNpmGlobals) { $totalSteps++ }
$script:totalSteps = $totalSteps

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
