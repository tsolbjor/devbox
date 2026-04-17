# =========================
# PARAMETERS (edit these)
# =========================

$Config = @{
  # Apps
  InstallWindowsTerminal = $true
  InstallVSCode          = $true
  InstallRancherDesktop  = $true
  InstallGit             = $true
  InstallPowerToys       = $true

  # Git for Windows global config (applied after Git is installed)
  GitConfig = @{
    Configure       = $true
    AutoCRLF        = "true"   # Windows: convert LF→CRLF on checkout (opposite of WSL's "input")
    DefaultBranch   = "main"
    PullRebase      = "false"
    AutoSetupRemote = "true"
  }
  Install7Zip            = $true
  InstallNode            = $true   # OpenJS.NodeJS.LTS + ncu global

  # Oh My Posh — prompt theme engine; configures PowerShell profiles for PS5 and PS7
  OhMyPosh = @{
    Configure = $true
    Theme     = "jandedobbeleer"   # name from https://ohmyposh.dev/docs/themes
  }

  # Fonts (winget IDs)
  Fonts = @(
    "Microsoft.CascadiaCode",
    "NERD-Fonts.JetBrainsMono"
  )

  # Cloud CLIs (remove any you don't need)
  CloudCLIs = @(
    "Microsoft.AzureCLI",
    "Amazon.AWSCLI",
    "Google.CloudSDK"
  )

  # Windows Terminal profile defaults (applied to all profiles via profiles.defaults)
  WindowsTerminalConfig = @{
    Configure          = $true
    FontPackageId      = "NERD-Fonts.JetBrainsMono"
    FontDownloadUrl    = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"
    FontArchiveFilter  = "JetBrainsMonoNerdFontMono-*.ttf"
    FontFace           = "JetBrainsMono Nerd Font Mono"
    FontFaceCandidates = @(
      "JetBrainsMono Nerd Font Mono",
      "JetBrainsMono NFM",
      "JetBrainsMono Nerd Font",
      "JetBrainsMono NF"
    )
    FontSize           = 12
    ColorScheme        = "One Half Dark"      # built-in scheme, good contrast
    CursorShape        = "bar"                # "bar", "vintage", "underscore", "filledBox", "emptyBox"
    BellStyle          = "none"
    HistorySize        = 30000
    # Tab contrast: active tab matches terminal bg; inactive tabs and tab row are darker
    ThemeName          = "devbox"
    ThemeTabActive     = "#282C34"   # One Half Dark background — selected tab appears open
    ThemeTabInactive   = "#1A1D23"   # ~35% darker — inactive tabs and tab row recede
  }

  # WSL / Ubuntu
  EnsureWSL              = $true
  WslDefaultVersion      = 2
  UbuntuDistroName       = "Ubuntu"   # e.g. "Ubuntu", "Ubuntu-22.04", "Ubuntu-24.04"
  SetUbuntuAsDefaultInWindowsTerminal = $true

  # WSL resource limits (writes ~/.wslconfig on Windows side).
  # Set memory/processors/swap to $null to auto-detect (75% of system resources;
  # swap is disabled automatically when the allocated RAM is >= 16 GB).
  WslConfig = @{
    memory          = $null   # e.g. "8GB", or $null to auto-detect
    processors      = $null   # e.g. 4,   or $null to auto-detect
    swap            = $null   # e.g. 0 (disable), "4GB", or $null to auto-detect
    networkingMode  = "mirrored"  # "mirrored" requires Windows 11 22H2+ / WSL 2.0; use "nat" for older systems
    localhostForwarding = $null   # Ignored by WSL when networkingMode=mirrored; set only for NAT mode
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

  # Windows system settings
  EnableLongPaths        = $true   # removes 260-char path limit
  EnableOpenSSHAgent     = $true   # allows SSH key forwarding across the WSL boundary
  ExcludeWslFromDefender = $true   # excludes WSL vhdx from real-time scanning

  # VS Code extensions installed on Windows (not inside containers)
  VSCodeExtensions = @(
    "ms-vscode-remote.remote-wsl",
    "ms-vscode-remote.remote-containers",
    "ms-azuretools.vscode-docker"
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
  $swap  = if ($memGB -ge 16) { 0 } else { $null }   # disable swap on high-RAM machines
  return @{ MemoryGB = $memGB; CPUs = $cpus; Swap = $swap }
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

function Get-InstalledFontFamilies {
  $fontFamilies = [System.Collections.Generic.List[string]]::new()

  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    foreach ($family in (New-Object System.Drawing.Text.InstalledFontCollection).Families) {
      if ($family.Name) {
        [void]$fontFamilies.Add($family.Name)
      }
    }
  } catch {
    Write-Warning "Could not enumerate installed fonts via System.Drawing. Falling back to the Windows font registry."
  }

  foreach ($fontKeyPath in @(
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
    "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  )) {
    if (-not (Test-Path $fontKeyPath)) { continue }

    try {
      $fontKey = Get-ItemProperty -Path $fontKeyPath
      foreach ($prop in $fontKey.PSObject.Properties) {
        if ($prop.Name -in @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
          continue
        }

        $familyName = ($prop.Name -replace '\s*\(.+\)$', '').Trim()
        if ($familyName) {
          [void]$fontFamilies.Add($familyName)
        }
      }
    } catch {
      Write-Warning "Could not read registered fonts from $fontKeyPath."
    }
  }

  return $fontFamilies | Select-Object -Unique
}

function Resolve-WindowsTerminalFontFace {
  param(
    [Parameter(Mandatory=$true)][string]$PreferredFontFace
  )

  $installedFonts = Get-InstalledFontFamilies
  if ($installedFonts.Count -eq 0) {
    return $PreferredFontFace
  }

  $candidates = @(
    $PreferredFontFace,
    "JetBrainsMono Nerd Font Mono",
    "JetBrainsMono Nerd Font Propo",
    "JetBrainsMono NFM",
    "JetBrainsMono NFP",
    "JetBrainsMono NF",
    "CaskaydiaCove Nerd Font",
    "CaskaydiaMono Nerd Font",
    "Cascadia Code"
  ) | Select-Object -Unique

  foreach ($candidate in $candidates) {
    if ($installedFonts -contains $candidate) {
      if ($candidate -ne $PreferredFontFace) {
        Write-Warning "Windows Terminal font '$PreferredFontFace' is not installed. Using '$candidate' instead."
      }
      return $candidate
    }
  }

  Write-Warning "None of the preferred Terminal fonts were found. Leaving font face as '$PreferredFontFace'."
  return $PreferredFontFace
}

function Ensure-FontPackageRegistered {
  param(
    [Parameter(Mandatory=$true)][string]$PackageId,
    [Parameter(Mandatory=$true)][string[]]$FontFaces,
    [int]$MaxAttempts = 5,
    [int]$RetryDelaySeconds = 2
  )

  Install-WingetPackage -Id $PackageId

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $installedFonts = Get-InstalledFontFamilies
    $matchedFace = $FontFaces | Where-Object { $installedFonts -contains $_ } | Select-Object -First 1
    if ($matchedFace) {
      Write-Host "✓ Font registered: $matchedFace" -ForegroundColor Green
      return $matchedFace
    }

    if ($attempt -lt $MaxAttempts) {
      Write-Host "→ Waiting for font registration: $PackageId (attempt $attempt/$MaxAttempts)" -ForegroundColor Cyan
      Start-Sleep -Seconds $RetryDelaySeconds
    }
  }

  Write-Warning "Installed '$PackageId', but Windows did not register any expected font family: $($FontFaces -join ', ')."
  Write-Warning "A sign out or reboot may still be required before Windows Terminal can use the new font."
  return $null
}

function Wait-ForFontRegistration {
  param(
    [Parameter(Mandatory=$true)][string[]]$FontFaces,
    [int]$MaxAttempts = 10,
    [int]$RetryDelaySeconds = 2,
    [string]$StatusLabel = "fonts"
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $installedFonts = Get-InstalledFontFamilies
    $matchedFace = $FontFaces | Where-Object { $installedFonts -contains $_ } | Select-Object -First 1
    if ($matchedFace) {
      Write-Host "✓ Font registered: $matchedFace" -ForegroundColor Green
      return $matchedFace
    }

    if ($attempt -lt $MaxAttempts) {
      Write-Host "→ Waiting for font registration: $StatusLabel (attempt $attempt/$MaxAttempts)" -ForegroundColor Cyan
      Start-Sleep -Seconds $RetryDelaySeconds
    }
  }

  return $null
}

function Install-NerdFontArchive {
  param(
    [Parameter(Mandatory=$true)][string]$PackageId,
    [Parameter(Mandatory=$true)][string]$DownloadUrl,
    [Parameter(Mandatory=$true)][string[]]$FontFaces,
    [string]$ArchiveFilter = "*"
  )

  $matchedFace = Wait-ForFontRegistration -FontFaces $FontFaces -MaxAttempts 1 -StatusLabel $PackageId
  if ($matchedFace) {
    return $matchedFace
  }

  $tempRoot = Join-Path $env:TEMP "devbox-fonts"
  $packageDir = Join-Path $tempRoot ($PackageId -replace '[^A-Za-z0-9._-]', '_')
  $zipName = Split-Path $DownloadUrl -Leaf
  $zipPath = Join-Path $packageDir $zipName
  $extractDir = Join-Path $packageDir "expanded"
  $installDir = Join-Path $packageDir "install"

  if (-not (Test-Path $packageDir)) {
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
  }

  Write-Host "→ Downloading font archive: $DownloadUrl" -ForegroundColor Cyan
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath

  if (Test-Path $extractDir) {
    Remove-Item -Path $extractDir -Recurse -Force
  }
  if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
  }
  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

  $fontFiles = Get-ChildItem -Path $extractDir -Recurse -Include *.ttf,*.otf -File |
    Where-Object {
      $_.Name -notmatch 'Windows Compatible' -and
      $_.Name -like $ArchiveFilter
    }

  if (-not $fontFiles) {
    throw "No font files matching '$ArchiveFilter' found in downloaded archive: $DownloadUrl"
  }

  New-Item -ItemType Directory -Path $installDir -Force | Out-Null
  foreach ($fontFile in $fontFiles) {
    Copy-Item -Path $fontFile.FullName -Destination (Join-Path $installDir $fontFile.Name) -Force
  }

  $fontsFolder = (New-Object -ComObject Shell.Application).Namespace(0x14)
  if (-not $fontsFolder) {
    throw "Could not access the Windows Fonts shell folder."
  }
  $installFolder = (New-Object -ComObject Shell.Application).Namespace($installDir)
  if (-not $installFolder) {
    throw "Could not access the staged font folder: $installDir"
  }

  Write-Host "→ Installing $($fontFiles.Count) font files matching '$ArchiveFilter'" -ForegroundColor Cyan
  $fontsFolder.CopyHere($installFolder.Items(), 0x10)
  Start-Sleep -Seconds 2

  $matchedFace = Wait-ForFontRegistration -FontFaces $FontFaces -StatusLabel $PackageId
  if ($matchedFace) {
    return $matchedFace
  }

  Write-Warning "Installed font files for '$PackageId', but Windows did not register any expected font family: $($FontFaces -join ', ')."
  Write-Warning "A sign out or reboot may still be required before Windows Terminal can use the new font."
  return $null
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
  $isMirroredNetworking = $WslConfig.networkingMode -eq "mirrored"

  $desired = @()
  $desired += "[wsl2]"
  if ($WslConfig.memory) { $desired += "memory=$($WslConfig.memory)" }
  if ($WslConfig.processors) { $desired += "processors=$($WslConfig.processors)" }
  if ($null -ne $WslConfig.swap) { $desired += "swap=$($WslConfig.swap)" }
  if ($WslConfig.networkingMode) { $desired += "networkingMode=$($WslConfig.networkingMode)" }
  if ($isMirroredNetworking -and $null -ne $WslConfig.localhostForwarding) {
    Write-Warning "Skipping localhostForwarding because WSL ignores it when networkingMode=mirrored."
  } elseif ($null -ne $WslConfig.localhostForwarding) {
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

function Ensure-OhMyPoshPowerShell {
  param([Parameter(Mandatory=$true)][string]$Theme)

  Install-WingetPackage -Id "JanDeDobbeleer.OhMyPosh"

  $docs = [Environment]::GetFolderPath("MyDocuments")
  $targets = @(
    @{ Profile = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Shell = "powershell" }
    @{ Profile = Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1";        Shell = "pwsh" }
  )

  foreach ($t in $targets) {
    $exe = if ($t.Shell -eq "pwsh") { "pwsh" } else { "powershell" }
    if (-not (Test-Command $exe)) { continue }

    $dir = Split-Path $t.Profile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $content = if (Test-Path $t.Profile) { Get-Content $t.Profile -Raw } else { "" }
    if ($content -match "oh-my-posh") {
      Write-Host "✓ oh-my-posh already in: $($t.Profile)" -ForegroundColor Green
      continue
    }

    # Write literal $env:POSH_THEMES_PATH so it expands at shell startup, not now
    $initLine = "oh-my-posh init $($t.Shell) --config `"`$env:POSH_THEMES_PATH\$Theme.omp.json`" | Invoke-Expression"
    Write-Host "→ Adding oh-my-posh to: $($t.Profile)" -ForegroundColor Cyan
    if ($content) {
      Add-Content -Path $t.Profile -Value "`n$initLine" -Encoding UTF8
    } else {
      Set-Content -Path $t.Profile -Value $initLine -Encoding UTF8
    }
    Write-Host "✓ oh-my-posh configured in: $($t.Profile)" -ForegroundColor Green
  }
}

function Ensure-WindowsTerminalProfileDefaults {
  param($WtConfig)

  $settingsPath = Get-WindowsTerminalSettingsPath
  if (-not $settingsPath) {
    Write-Warning "Windows Terminal settings.json not found. Open Windows Terminal once, then rerun."
    return
  }

  $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
  $changed = $false
  $resolvedFontFace = Resolve-WindowsTerminalFontFace -PreferredFontFace $WtConfig.FontFace

  # Ensure profiles.defaults path exists
  if ($null -eq $json.profiles) {
    $json | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  if ($null -eq $json.profiles.defaults) {
    $json.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  $d = $json.profiles.defaults

  # Font (nested object)
  if ($null -eq $d.font -or $d.font -isnot [psobject]) {
    $d | Add-Member -NotePropertyName "font" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  $currentFontFaceProp = $d.font.PSObject.Properties["face"]
  $currentFontFace = if ($null -ne $currentFontFaceProp) { $currentFontFaceProp.Value } else { $null }
  if ($currentFontFace -ne $resolvedFontFace) {
    $d.font | Add-Member -NotePropertyName "face" -NotePropertyValue $resolvedFontFace -Force
    $changed = $true
  }
  $currentFontSizeProp = $d.font.PSObject.Properties["size"]
  $currentFontSize = if ($null -ne $currentFontSizeProp) { $currentFontSizeProp.Value } else { $null }
  if ($currentFontSize -ne $WtConfig.FontSize) {
    $d.font | Add-Member -NotePropertyName "size" -NotePropertyValue $WtConfig.FontSize -Force
    $changed = $true
  }

  # Flat settings
  foreach ($pair in @(
    @{ Key = "colorScheme"; Val = $WtConfig.ColorScheme },
    @{ Key = "cursorShape"; Val = $WtConfig.CursorShape },
    @{ Key = "bellStyle";   Val = $WtConfig.BellStyle },
    @{ Key = "historySize"; Val = $WtConfig.HistorySize }
  )) {
    $currentProp = $d.PSObject.Properties[$pair.Key]
    $currentVal = if ($null -ne $currentProp) { $currentProp.Value } else { $null }
    if ($currentVal -ne $pair.Val) {
      $d | Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Val -Force
      $changed = $true
    }
  }

  if ($changed) {
    Write-Host "→ Updating Windows Terminal profile defaults: $settingsPath" -ForegroundColor Cyan
    ($json | ConvertTo-Json -Depth 50) | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Host "✓ Windows Terminal profile defaults configured." -ForegroundColor Green
  } else {
    Write-Host "✓ Windows Terminal profile defaults already match desired settings." -ForegroundColor Green
  }
}

function Ensure-WindowsTerminalTheme {
  param($WtConfig)

  $settingsPath = Get-WindowsTerminalSettingsPath
  if (-not $settingsPath) {
    Write-Warning "Windows Terminal settings.json not found. Open Windows Terminal once, then rerun."
    return
  }

  $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
  $changed = $false

  # Ensure top-level themes array exists
  if ($null -eq $json.PSObject.Properties["themes"]) {
    $json | Add-Member -NotePropertyName "themes" -NotePropertyValue @() -Force
  }

  # Find or create our named theme entry
  $theme = @($json.themes) | Where-Object { $_.name -eq $WtConfig.ThemeName } | Select-Object -First 1
  if ($null -eq $theme) {
    $theme = [PSCustomObject]@{ name = $WtConfig.ThemeName }
    $json.themes = @($json.themes) + @($theme)
    $changed = $true
  }

  # tab: active tab bg, inactive tab bg
  if ($null -eq $theme.PSObject.Properties["tab"]) {
    $theme | Add-Member -NotePropertyName "tab" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  foreach ($pair in @(
    @{ Key = "background";          Val = $WtConfig.ThemeTabActive },
    @{ Key = "unfocusedBackground"; Val = $WtConfig.ThemeTabInactive }
  )) {
    $p = $theme.tab.PSObject.Properties[$pair.Key]
    if ($null -eq $p -or $p.Value -ne $pair.Val) {
      $theme.tab | Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Val -Force
      $changed = $true
    }
  }

  # tabRow: background behind all tabs
  if ($null -eq $theme.PSObject.Properties["tabRow"]) {
    $theme | Add-Member -NotePropertyName "tabRow" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  foreach ($pair in @(
    @{ Key = "background";          Val = $WtConfig.ThemeTabInactive },
    @{ Key = "unfocusedBackground"; Val = $WtConfig.ThemeTabInactive }
  )) {
    $p = $theme.tabRow.PSObject.Properties[$pair.Key]
    if ($null -eq $p -or $p.Value -ne $pair.Val) {
      $theme.tabRow | Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Val -Force
      $changed = $true
    }
  }

  # window: lock to dark application theme
  if ($null -eq $theme.PSObject.Properties["window"]) {
    $theme | Add-Member -NotePropertyName "window" -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  $p = $theme.window.PSObject.Properties["applicationTheme"]
  if ($null -eq $p -or $p.Value -ne "dark") {
    $theme.window | Add-Member -NotePropertyName "applicationTheme" -NotePropertyValue "dark" -Force
    $changed = $true
  }

  # Activate the theme at the top level
  $p = $json.PSObject.Properties["theme"]
  if ($null -eq $p -or $p.Value -ne $WtConfig.ThemeName) {
    $json | Add-Member -NotePropertyName "theme" -NotePropertyValue $WtConfig.ThemeName -Force
    $changed = $true
  }

  if ($changed) {
    Write-Host "→ Applying Windows Terminal theme '$($WtConfig.ThemeName)': $settingsPath" -ForegroundColor Cyan
    ($json | ConvertTo-Json -Depth 50) | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Host "✓ Tab contrast configured (active: $($WtConfig.ThemeTabActive), inactive: $($WtConfig.ThemeTabInactive))" -ForegroundColor Green
  } else {
    Write-Host "✓ Windows Terminal theme '$($WtConfig.ThemeName)' already matches desired settings" -ForegroundColor Green
  }
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

  $rdRunning = Get-Process | Where-Object { $_.Name -like "*rancher*desktop*" }
  if ($rdRunning) {
    Write-Warning "Rancher Desktop is currently running. Close it before rerunning so settings are not overwritten by the live process."
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

function Ensure-NodeAndNcu {
  Install-WingetPackage -Id "OpenJS.NodeJS.LTS"

  # Refresh PATH so npm is available in this session after a fresh install
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path", "User")

  if (-not (Test-Command "npm")) {
    Write-Warning "npm not found in PATH after Node.js install. Open a new terminal and run: npm install -g npm-check-updates"
    return
  }

  if (Test-Command "ncu") {
    Write-Host "✓ ncu already installed" -ForegroundColor Green
  } else {
    Write-Host "→ Installing ncu (npm-check-updates)" -ForegroundColor Cyan
    npm install -g npm-check-updates
    Write-Host "✓ ncu installed" -ForegroundColor Green
  }
}

function Ensure-GitSetting {
  param(
    [Parameter(Mandatory=$true)][string]$Key,
    [Parameter(Mandatory=$true)][string]$Value
  )
  $current = git config --global --get $Key 2>$null
  if ($current -eq $Value) {
    Write-Host "✓ git config $Key = $Value" -ForegroundColor Green
    return
  }
  Write-Host "→ Setting git config $Key = $Value" -ForegroundColor Cyan
  git config --global $Key $Value
}

function Ensure-WindowsGitConfig {
  param($GitConfig)
  if (-not (Test-Command "git")) {
    Write-Warning "git not in PATH yet — open a new terminal after installation and rerun to apply git config."
    return
  }
  Ensure-GitSetting "core.autocrlf"        $GitConfig.AutoCRLF
  Ensure-GitSetting "init.defaultBranch"   $GitConfig.DefaultBranch
  Ensure-GitSetting "pull.rebase"          $GitConfig.PullRebase
  Ensure-GitSetting "push.autoSetupRemote" $GitConfig.AutoSetupRemote
}

function Enable-LongPaths {
  $key = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
  $current = (Get-ItemProperty -Path $key -Name "LongPathsEnabled" -ErrorAction SilentlyContinue).LongPathsEnabled
  if ($current -eq 1) {
    Write-Host "✓ Long path support already enabled." -ForegroundColor Green
    return
  }
  Write-Host "→ Enabling long path support." -ForegroundColor Cyan
  Set-ItemProperty -Path $key -Name "LongPathsEnabled" -Value 1 -Type DWord
  Write-Host "✓ Long path support enabled." -ForegroundColor Green
}

function Enable-OpenSSHAgent {
  $svc = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
  if (-not $svc) {
    Write-Warning "OpenSSH Authentication Agent service not found. Enable OpenSSH Client in Settings → Optional Features, then rerun."
    return
  }
  if ($svc.StartType -eq "Automatic" -and $svc.Status -eq "Running") {
    Write-Host "✓ OpenSSH Authentication Agent already running (Automatic)." -ForegroundColor Green
    return
  }
  Write-Host "→ Setting OpenSSH Authentication Agent to Automatic and starting it." -ForegroundColor Cyan
  Set-Service -Name "ssh-agent" -StartupType Automatic
  Start-Service -Name "ssh-agent"
  Write-Host "✓ OpenSSH Authentication Agent enabled." -ForegroundColor Green
}

$script:currentStep = 0
$script:totalSteps  = 0

function Show-Progress {
  param([Parameter(Mandatory=$true)][string]$Status)
  $script:currentStep++
  $pct = [int]($script:currentStep / $script:totalSteps * 100)
  Write-Progress -Activity "devbox setup" -Status "[$($script:currentStep)/$($script:totalSteps)] $Status" -PercentComplete $pct
  Write-Host "`n[$($script:currentStep)/$($script:totalSteps)] $Status" -ForegroundColor White
}

function Add-WslDefenderExclusion {
  $packagesPath = Join-Path $env:LOCALAPPDATA "Packages"
  $existing = (Get-MpPreference).ExclusionPath | Where-Object { $_ -like "*CanonicalGroupLimited*" }
  if ($existing) {
    Write-Host "✓ Windows Defender WSL exclusion already configured." -ForegroundColor Green
    return
  }
  $wslDirs = Get-ChildItem -Path $packagesPath -Filter "CanonicalGroupLimited*" -Directory -ErrorAction SilentlyContinue
  if (-not $wslDirs) {
    Write-Warning "No WSL package directories found under $packagesPath. Run after WSL is installed."
    return
  }
  foreach ($dir in $wslDirs) {
    $localState = Join-Path $dir.FullName "LocalState"
    if (Test-Path $localState) {
      Write-Host "→ Adding Defender exclusion: $localState" -ForegroundColor Cyan
      Add-MpPreference -ExclusionPath $localState
    }
  }
  Write-Host "✓ WSL directories excluded from Windows Defender." -ForegroundColor Green
}

# =========================
# RUN
# =========================

Assert-Admin
Ensure-Winget

# Pre-compute total step count for progress display
$totalSteps = 4  # always: detect resources, install apps, configure WSL, apply system settings
if ($Config.Fonts.Count -gt 0)    { $totalSteps++ }
if ($Config.CloudCLIs.Count -gt 0) { $totalSteps++ }
if (($Config.SetUbuntuAsDefaultInWindowsTerminal -and $Config.InstallWindowsTerminal) -or $Config.WindowsTerminalConfig.Configure) { $totalSteps++ }
if ($Config.OhMyPosh.Configure)   { $totalSteps++ }
if ($Config.InstallVSCode -and $Config.VSCodeExtensions.Count -gt 0) { $totalSteps++ }
if ($Config.RancherDesktopConfig.Configure) { $totalSteps++ }
$script:totalSteps = $totalSteps

Show-Progress "Detecting system resources"
$sys   = Get-SystemResources
$alloc = Get-WslAllocation -TotalRAMGB $sys.TotalRAMGB -LogicalCPUs $sys.LogicalCPUs
Write-Host "System: $($sys.TotalRAMGB) GB RAM, $($sys.LogicalCPUs) logical CPUs" -ForegroundColor Cyan
$swapDisplay = if ($null -eq $alloc.Swap) { "WSL default" } else { $alloc.Swap }
Write-Host "WSL allocation (75%): $($alloc.MemoryGB) GB RAM, $($alloc.CPUs) CPUs, swap=$swapDisplay" -ForegroundColor Cyan

if (-not $Config.WslConfig.memory)     { $Config.WslConfig.memory     = "$($alloc.MemoryGB)GB" }
if (-not $Config.WslConfig.processors) { $Config.WslConfig.processors = $alloc.CPUs }
if ($null -eq $Config.WslConfig.swap -and $null -ne $alloc.Swap) { $Config.WslConfig.swap = $alloc.Swap }
if (-not $Config.RancherDesktopConfig.memoryInGB) { $Config.RancherDesktopConfig.memoryInGB = $alloc.MemoryGB }
if (-not $Config.RancherDesktopConfig.numberCPUs) { $Config.RancherDesktopConfig.numberCPUs = $alloc.CPUs }

Show-Progress "Installing apps"
if ($Config.InstallWindowsTerminal) { Install-WingetPackage -Id "Microsoft.WindowsTerminal" }
if ($Config.InstallVSCode)          { Install-WingetPackage -Id "Microsoft.VisualStudioCode" }
if ($Config.InstallRancherDesktop)  { Install-WingetPackage -Id "SUSE.RancherDesktop" }
if ($Config.InstallGit) {
  Install-WingetPackage -Id "Git.Git"
  if ($Config.GitConfig.Configure) { Ensure-WindowsGitConfig -GitConfig $Config.GitConfig }
}
if ($Config.InstallPowerToys)       { Install-WingetPackage -Id "Microsoft.PowerToys" }
if ($Config.Install7Zip)            { Install-WingetPackage -Id "7zip.7zip" }
if ($Config.InstallNode)            { Ensure-NodeAndNcu }

if ($Config.Fonts.Count -gt 0) {
  Show-Progress "Installing fonts"
  foreach ($font in $Config.Fonts) {
    if (
      $Config.WindowsTerminalConfig.Configure -and
      $font -eq $Config.WindowsTerminalConfig.FontPackageId -and
      $Config.WindowsTerminalConfig.FontFaceCandidates.Count -gt 0 -and
      $Config.WindowsTerminalConfig.FontDownloadUrl
    ) {
      Install-NerdFontArchive `
        -PackageId $font `
        -DownloadUrl $Config.WindowsTerminalConfig.FontDownloadUrl `
        -FontFaces $Config.WindowsTerminalConfig.FontFaceCandidates `
        -ArchiveFilter $Config.WindowsTerminalConfig.FontArchiveFilter | Out-Null
      continue
    }

    Install-WingetPackage -Id $font
  }
}

if ($Config.CloudCLIs.Count -gt 0) {
  Show-Progress "Installing cloud CLIs"
  foreach ($cli in $Config.CloudCLIs) { Install-WingetPackage -Id $cli }
}

Show-Progress "Configuring WSL"
if ($Config.EnsureWSL) {
  Ensure-WSL -DistroName $Config.UbuntuDistroName -DefaultVersion $Config.WslDefaultVersion
}
Ensure-WSLConfigFile -WslConfig $Config.WslConfig

if (($Config.SetUbuntuAsDefaultInWindowsTerminal -and $Config.InstallWindowsTerminal) -or $Config.WindowsTerminalConfig.Configure) {
  Show-Progress "Configuring Windows Terminal"
  if ($Config.SetUbuntuAsDefaultInWindowsTerminal -and $Config.InstallWindowsTerminal) {
    Ensure-WindowsTerminalDefaultProfileUbuntu -UbuntuName $Config.UbuntuDistroName
  }
  if ($Config.WindowsTerminalConfig.Configure) {
    Ensure-WindowsTerminalProfileDefaults -WtConfig $Config.WindowsTerminalConfig
    Ensure-WindowsTerminalTheme -WtConfig $Config.WindowsTerminalConfig
  }
}

if ($Config.OhMyPosh.Configure) {
  Show-Progress "Configuring Oh My Posh"
  Ensure-OhMyPoshPowerShell -Theme $Config.OhMyPosh.Theme
}

if ($Config.InstallVSCode -and $Config.VSCodeExtensions.Count -gt 0) {
  Show-Progress "Installing VS Code extensions"
  Ensure-VSCodeExtensions -Extensions $Config.VSCodeExtensions
}

if ($Config.RancherDesktopConfig.Configure) {
  Show-Progress "Configuring Rancher Desktop"
  Ensure-RancherDesktopConfig -RdConfig $Config.RancherDesktopConfig
}

Show-Progress "Applying system settings"
if ($Config.EnableLongPaths)        { Enable-LongPaths }
if ($Config.EnableOpenSSHAgent)     { Enable-OpenSSHAgent }
if ($Config.ExcludeWslFromDefender) { Add-WslDefenderExclusion }

Write-Progress -Activity "devbox setup" -Completed
Write-Host "`nDone." -ForegroundColor Green
Write-Host "Tip: Apply WSL resource changes with: wsl --shutdown" -ForegroundColor Cyan
Write-Host "Tip: Restart Rancher Desktop to apply VM resource changes." -ForegroundColor Cyan
