# =========================
# PARAMETERS (edit these)
# =========================

$Config = @{
  # Apps
  InstallWindowsTerminal = $true
  InstallVSCode          = $true
  InstallRancherDesktop  = $true

  # WSL / Ubuntu
  EnsureWSL              = $true
  WslDefaultVersion      = 2
  UbuntuDistroName       = "Ubuntu"   # e.g. "Ubuntu", "Ubuntu-22.04", "Ubuntu-24.04"
  SetUbuntuAsDefaultInWindowsTerminal = $true

  # WSL resource limits (writes ~/.wslconfig on Windows side).
  # Set memory/processors to $null to auto-detect (75% of system resources).
  WslConfig = @{
    memory     = $null   # e.g. "8GB", or $null to auto-detect
    processors = $null   # e.g. 4,   or $null to auto-detect
    localhostForwarding = $true
  }

  # Rancher Desktop VM + Kubernetes settings.
  # memoryInGB / numberCPUs: $null = match WSL allocation.
  RancherDesktopConfig = @{
    Configure         = $true
    memoryInGB        = $null   # $null = match WSL allocation
    numberCPUs        = $null   # $null = match WSL allocation
    containerEngine   = "moby"  # "moby" for Docker-compatible CLI
    kubernetesEnabled = $true
  }

  # Optional: VS Code extensions installed on Windows (not inside containers)
  VSCodeExtensions = @(
    "ms-vscode-remote.remote-wsl",
    "ms-vscode-remote.remote-containers"
  )
}

# =========================
# IMPLEMENTATION
# =========================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SystemResources {
  $cs = Get-CimInstance Win32_ComputerSystem
  return @{
    TotalRAMGB   = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    LogicalCPUs  = [int]$cs.NumberOfLogicalProcessors
  }
}

function Get-WslAllocation {
  param($TotalRAMGB, $LogicalCPUs)
  $memGB = [Math]::Max(2, [Math]::Floor($TotalRAMGB * 0.75))
  $cpus  = [Math]::Max(1, [Math]::Floor($LogicalCPUs * 0.75))
  return @{ MemoryGB = $memGB; CPUs = $cpus }
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

function Ensure-Winget {
  if (-not (Test-Command "winget")) {
    throw "winget is not available. Install 'App Installer' from Microsoft Store (or ensure winget is present), then rerun."
  }
}

function Install-WingetPackage {
  param(
    [Parameter(Mandatory=$true)][string]$Id
  )
  $list = winget list --id $Id --accept-source-agreements 2>$null | Out-String
  if ($list -match [regex]::Escape($Id)) {
    Write-Host "✓ Already installed: $Id" -ForegroundColor Green
    return
  }

  Write-Host "→ Installing: $Id" -ForegroundColor Cyan
  winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements
}

function Ensure-WindowsOptionalFeatureEnabled {
  param(
    [Parameter(Mandatory=$true)][string]$FeatureName
  )
  $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName
  if ($feature.State -eq "Enabled") {
    Write-Host "✓ Feature enabled: $FeatureName" -ForegroundColor Green
    return $false
  }
  Write-Host "→ Enabling feature: $FeatureName" -ForegroundColor Cyan
  Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart | Out-Null
  return $true
}

function Ensure-WSL {
  param(
    [Parameter(Mandatory=$true)][string]$DistroName,
    [Parameter(Mandatory=$true)][int]$DefaultVersion
  )

  $restartNeeded = $false

  $restartNeeded = (Ensure-WindowsOptionalFeatureEnabled "Microsoft-Windows-Subsystem-Linux") -or $restartNeeded
  $restartNeeded = (Ensure-WindowsOptionalFeatureEnabled "VirtualMachinePlatform") -or $restartNeeded

  # Ensure WSL command is available
  if (-not (Test-Command "wsl")) {
    Write-Host "→ Installing WSL..." -ForegroundColor Cyan
    wsl --install | Out-Null
    $restartNeeded = $true
  }

  # Set default WSL version
  Write-Host "→ Setting WSL default version to $DefaultVersion" -ForegroundColor Cyan
  wsl --set-default-version $DefaultVersion | Out-Null

  # Ensure distro is installed
  $distros = (wsl -l -q 2>$null) | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  if ($distros -contains $DistroName) {
    Write-Host "✓ Distro installed: $DistroName" -ForegroundColor Green
  } else {
    Write-Host "→ Installing distro: $DistroName" -ForegroundColor Cyan
    # Note: wsl --install may still require a reboot depending on state.
    wsl --install -d $DistroName | Out-Null
    $restartNeeded = $true
  }

  if ($restartNeeded) {
    Write-Warning "One or more changes require a reboot to fully take effect. Reboot, then rerun this script."
  } else {
    Write-Host "✓ WSL looks ready." -ForegroundColor Green
  }
}

function Ensure-WSLConfigFile {
  param(
    [Parameter(Mandatory=$true)]$WslConfig
  )

  $path = Join-Path $env:USERPROFILE ".wslconfig"

  $desired = @()
  $desired += "[wsl2]"
  if ($WslConfig.memory) { $desired += "memory=$($WslConfig.memory)" }
  if ($WslConfig.processors) { $desired += "processors=$($WslConfig.processors)" }
  if ($null -ne $WslConfig.localhostForwarding) {
    $val = if ($WslConfig.localhostForwarding) { "true" } else { "false" }
    $desired += "localhostForwarding=$val"
  }
  $desiredText = ($desired -join "`r`n") + "`r`n"

  $current = ""
  if (Test-Path $path) { $current = Get-Content $path -Raw }

  if ($current -ne $desiredText) {
    Write-Host "→ Writing $path" -ForegroundColor Cyan
    Set-Content -Path $path -Value $desiredText -Encoding UTF8
    Write-Host "✓ Updated .wslconfig (run: wsl --shutdown to apply without reboot)." -ForegroundColor Green
  } else {
    Write-Host "✓ .wslconfig already matches desired settings." -ForegroundColor Green
  }
}

function Get-WindowsTerminalSettingsPath {
  $candidates = @(
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json")
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json")
  )
  foreach ($p in $candidates) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

function Ensure-WindowsTerminalDefaultProfileUbuntu {
  param(
    [Parameter(Mandatory=$true)][string]$UbuntuName
  )

  $settingsPath = Get-WindowsTerminalSettingsPath
  if (-not $settingsPath) {
    Write-Warning "Windows Terminal settings.json not found yet. Open Windows Terminal once, then rerun."
    return
  }

  $json = Get-Content $settingsPath -Raw | ConvertFrom-Json

  # Find an Ubuntu profile (name contains UbuntuName)
  $profiles = $json.profiles.list
  $ubuntu = $profiles | Where-Object { $_.name -like "*$UbuntuName*" } | Select-Object -First 1

  if (-not $ubuntu) {
    Write-Warning "Could not find a Windows Terminal profile matching '*$UbuntuName*'. Skipping defaultProfile change."
    return
  }

  if ($json.defaultProfile -eq $ubuntu.guid) {
    Write-Host "✓ Windows Terminal default profile already set to: $($ubuntu.name)" -ForegroundColor Green
    return
  }

  Write-Host "→ Setting Windows Terminal default profile to: $($ubuntu.name)" -ForegroundColor Cyan
  $json.defaultProfile = $ubuntu.guid

  # Preserve formatting reasonably
  ($json | ConvertTo-Json -Depth 50) | Set-Content -Path $settingsPath -Encoding UTF8
  Write-Host "✓ Updated Windows Terminal default profile." -ForegroundColor Green
}

function Ensure-VSCodeExtensions {
  param([string[]]$Extensions)

  if (-not (Test-Command "code")) {
    Write-Warning "VS Code 'code' command not found in PATH. Launch VS Code once and enable 'Shell Command: Install 'code' command', or rerun later."
    return
  }

  $installed = (code --list-extensions) 2>$null
  foreach ($ext in $Extensions) {
    if ($installed -contains $ext) {
      Write-Host "✓ VS Code extension installed: $ext" -ForegroundColor Green
    } else {
      Write-Host "→ Installing VS Code extension: $ext" -ForegroundColor Cyan
      code --install-extension $ext | Out-Null
    }
  }
}

function Ensure-RancherDesktopConfig {
  param($RdConfig)

  $settingsPath = Join-Path $env:APPDATA "rancher-desktop\settings.json"
  if (-not (Test-Path $settingsPath)) {
    Write-Warning "Rancher Desktop settings.json not found at $settingsPath. Launch Rancher Desktop once to initialise it, then rerun."
    return
  }

  $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
  $changed = $false

  # Virtual machine resources
  if ($null -eq $settings.virtualMachine) {
    $settings | Add-Member -NotePropertyName "virtualMachine" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  if ($settings.virtualMachine.memoryInGB -ne $RdConfig.memoryInGB) {
    $settings.virtualMachine.memoryInGB = $RdConfig.memoryInGB
    $changed = $true
  }
  if ($settings.virtualMachine.numberCPUs -ne $RdConfig.numberCPUs) {
    $settings.virtualMachine.numberCPUs = $RdConfig.numberCPUs
    $changed = $true
  }

  # Container engine (moby = Docker-compatible)
  if ($null -eq $settings.containerEngine) {
    $settings | Add-Member -NotePropertyName "containerEngine" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  if ($settings.containerEngine.name -ne $RdConfig.containerEngine) {
    $settings.containerEngine.name = $RdConfig.containerEngine
    $changed = $true
  }

  # Kubernetes
  if ($null -eq $settings.kubernetes) {
    $settings | Add-Member -NotePropertyName "kubernetes" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  if ($settings.kubernetes.enabled -ne $RdConfig.kubernetesEnabled) {
    $settings.kubernetes.enabled = $RdConfig.kubernetesEnabled
    $changed = $true
  }

  if ($changed) {
    Write-Host "→ Writing Rancher Desktop settings: $settingsPath" -ForegroundColor Cyan
    ($settings | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Host "✓ Rancher Desktop configured (restart Rancher Desktop to apply)." -ForegroundColor Green
  } else {
    Write-Host "✓ Rancher Desktop settings already match desired configuration." -ForegroundColor Green
  }
}

# =========================
# RUN
# =========================

Assert-Admin
Ensure-Winget

# Detect system resources and resolve any $null allocations to 75% of hardware
$sys   = Get-SystemResources
$alloc = Get-WslAllocation -TotalRAMGB $sys.TotalRAMGB -LogicalCPUs $sys.LogicalCPUs
Write-Host "System resources: $($sys.TotalRAMGB) GB RAM, $($sys.LogicalCPUs) logical CPUs" -ForegroundColor Cyan
Write-Host "WSL allocation (75%%): $($alloc.MemoryGB) GB RAM, $($alloc.CPUs) CPUs" -ForegroundColor Cyan

if (-not $Config.WslConfig.memory)     { $Config.WslConfig.memory     = "$($alloc.MemoryGB)GB" }
if (-not $Config.WslConfig.processors) { $Config.WslConfig.processors = $alloc.CPUs }
if (-not $Config.RancherDesktopConfig.memoryInGB) { $Config.RancherDesktopConfig.memoryInGB = $alloc.MemoryGB }
if (-not $Config.RancherDesktopConfig.numberCPUs) { $Config.RancherDesktopConfig.numberCPUs = $alloc.CPUs }

if ($Config.InstallWindowsTerminal) { Install-WingetPackage -Id "Microsoft.WindowsTerminal" }
if ($Config.InstallVSCode)          { Install-WingetPackage -Id "Microsoft.VisualStudioCode" }
if ($Config.InstallRancherDesktop)  { Install-WingetPackage -Id "SUSE.RancherDesktop" }

if ($Config.EnsureWSL) {
  Ensure-WSL -DistroName $Config.UbuntuDistroName -DefaultVersion $Config.WslDefaultVersion
}

Ensure-WSLConfigFile -WslConfig $Config.WslConfig

if ($Config.SetUbuntuAsDefaultInWindowsTerminal -and $Config.InstallWindowsTerminal) {
  Ensure-WindowsTerminalDefaultProfileUbuntu -UbuntuName $Config.UbuntuDistroName
}

if ($Config.InstallVSCode -and $Config.VSCodeExtensions.Count -gt 0) {
  Ensure-VSCodeExtensions -Extensions $Config.VSCodeExtensions
}

if ($Config.RancherDesktopConfig.Configure) {
  Ensure-RancherDesktopConfig -RdConfig $Config.RancherDesktopConfig
}

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Tip: Apply WSL resource changes with: wsl --shutdown" -ForegroundColor Cyan
Write-Host "Tip: Restart Rancher Desktop to apply VM resource changes." -ForegroundColor Cyan