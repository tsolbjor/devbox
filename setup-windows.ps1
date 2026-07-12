# =========================
# PARAMETERS (edit these)
# =========================

$Config = @{
  # Apps
  InstallWezTerm         = $true
  InstallPowerShell7     = $true   # pwsh — used by the WezTerm launcher + Starship pwsh profile
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
  InstallNode            = $true   # host Node for npm-global tooling (CDK, etc.)
  InstallAzureFunctionsCoreTools = $true   # `func` CLI via winget (self-updates on `winget upgrade`)

  # Starship — cross-shell prompt engine; configures PowerShell profiles for PS5 and PS7
  Starship = @{
    Configure = $true
    Preset    = "nerd-font-symbols"   # `starship preset --list`; "" keeps starship's built-in default
  }

  # PowerShell experience — fzf + PSFzf (Ctrl+T / Ctrl+R) and PSReadLine predictive IntelliSense
  ConfigurePwshExtras = $true

  # Fonts (winget IDs)
  Fonts = @(
    "Microsoft.CascadiaCode",
    "NERD-Fonts.JetBrainsMono"
  )

  # Cloud CLIs (remove any you don't need; add Amazon.AWSCLI / Google.CloudSDK if multi-cloud)
  CloudCLIs = @(
    "Microsoft.AzureCLI"
  )

  # WezTerm appearance — written to a managed ~/.wezterm.lua (overwritten on rerun)
  WezTermConfig = @{
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
    ColorScheme        = "OneHalfDark"   # built-in WezTerm scheme (matches the old One Half Dark)
    CursorStyle        = "SteadyBar"     # "SteadyBar", "BlinkingBar", "SteadyBlock", "SteadyUnderline", ...
    AudibleBell        = "Disabled"      # "Disabled" or "SystemBeep"
    ScrollbackLines    = 30000
    # Quick shell-switching: the (+) tab-bar dropdown lists these, and Ctrl+Shift+1/2/3
    # spawn cmd / pwsh / Ubuntu directly. Ctrl+Shift+L opens the launcher menu.
    PwshStartDir       = "D:\code"       # pwsh (Ctrl+Shift+2) opens here
  }

  # WSL / Ubuntu
  EnsureWSL              = $true
  WslDefaultVersion      = 2
  UbuntuDistroName       = "Ubuntu"   # e.g. "Ubuntu", "Ubuntu-22.04", "Ubuntu-24.04"
  SetWslAsDefaultInWezTerm = $true    # WezTerm opens the WSL distro by default (WSL:<distro> domain)

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

  # Relocate Windows-host package caches onto the Dev Drive (created by
  # bootstrap-windows.ps1). Keeping caches on the trusted ReFS Dev Drive is
  # Microsoft's recommended layout — faster restores, skipped from AV scanning.
  # Sets per-user environment variables; only affects host tooling (npm/nuget on
  # Windows). WSL/.NET-in-Linux caches live in the Linux filesystem, untouched.
  DevDrivePackageCaches = @{
    Configure = $true
    Root      = "D:\packages"   # must be on the Dev Drive for the perf/trust benefit
    Npm       = $true           # npm_config_cache
    NuGet     = $true           # NUGET_PACKAGES + http/plugins caches
  }
}

# =========================
# IMPLEMENTATION
# =========================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# wsl.exe emits UTF-16LE by default; in Windows PowerShell 5.1 that leaves embedded
# null bytes in captured output, so string matches (e.g. `-contains "Ubuntu"`) silently
# fail. Forcing UTF-8 makes wsl output parse cleanly. (WSL 0.64+; harmless if ignored.)
$env:WSL_UTF8 = 1

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

function Resolve-InstalledFontFace {
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
        Write-Warning "Font '$PreferredFontFace' is not installed. Using '$candidate' instead."
      }
      return $candidate
    }
  }

  Write-Warning "None of the preferred fonts were found. Leaving font face as '$PreferredFontFace'."
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
  Write-Warning "A sign out or reboot may still be required before apps can use the new font."
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
  Write-Warning "A sign out or reboot may still be required before apps can use the new font."
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
    Write-Host ""
    Write-Warning "WSL features / distro install require a reboot before setup can continue."
    Write-Host @"

  This is a multi-pass setup on a fresh machine:
    PASS 1 (done)  Enabled WSL features / started distro install.
    -> REBOOT NOW, then rerun this script (PASS 2).
    PASS 2         Finishes distro install + WezTerm / Rancher / Defender config.
                   (App config steps warn-and-skip until each app has launched once.)
    THEN           Launch Ubuntu once to create your UNIX user, then inside WSL run:
                     bash setup-ubuntu.sh
                   Git name/email auto-detect from the Windows (Entra) user. To override:
                     export GIT_NAME="Your Name"; export GIT_EMAIL="your@email.com"
"@ -ForegroundColor Yellow
    exit 0
  }

  Write-Host "✓ WSL looks ready." -ForegroundColor Green
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

function Ensure-StarshipPowerShell {
  param([string]$Preset)

  Install-WingetPackage -Id "Starship.Starship"

  # Refresh PATH so `starship` is callable in this session after a fresh install
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path", "User")

  # Apply a preset once — never clobber an existing starship.toml the user may have edited
  if ($Preset) {
    $cfgDir  = Join-Path $env:USERPROFILE ".config"
    $cfgPath = Join-Path $cfgDir "starship.toml"
    if (Test-Path $cfgPath) {
      Write-Host "✓ starship.toml already present: $cfgPath" -ForegroundColor Green
    } elseif (Test-Command "starship") {
      if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
      Write-Host "→ Applying starship preset '$Preset': $cfgPath" -ForegroundColor Cyan
      starship preset $Preset -o $cfgPath
      Write-Host "✓ starship preset applied." -ForegroundColor Green
    } else {
      Write-Warning "starship not on PATH yet — open a new terminal and run: starship preset $Preset -o `"$cfgPath`""
    }
  }

  $docs = [Environment]::GetFolderPath("MyDocuments")
  $targets = @(
    @{ Profile = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Exe = "powershell" }
    @{ Profile = Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1";        Exe = "pwsh" }
  )

  foreach ($t in $targets) {
    if (-not (Test-Command $t.Exe)) { continue }

    $dir = Split-Path $t.Profile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $content = if (Test-Path $t.Profile) { Get-Content $t.Profile -Raw } else { "" }
    if ($content -match "starship init") {
      Write-Host "✓ starship already in: $($t.Profile)" -ForegroundColor Green
      continue
    }

    $initLine = 'Invoke-Expression (&starship init powershell)'
    Write-Host "→ Adding starship to: $($t.Profile)" -ForegroundColor Cyan
    if ($content) {
      Add-Content -Path $t.Profile -Value "`n$initLine" -Encoding UTF8
    } else {
      Set-Content -Path $t.Profile -Value $initLine -Encoding UTF8
    }
    Write-Host "✓ starship configured in: $($t.Profile)" -ForegroundColor Green
  }
}

function Ensure-PSGalleryModule {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [string]$MinimumVersion
  )
  $present = Get-Module -ListAvailable -Name $Name |
    Where-Object { -not $MinimumVersion -or $_.Version -ge [version]$MinimumVersion }
  if ($present) {
    Write-Host "✓ PowerShell module present: $Name" -ForegroundColor Green
    return
  }
  Write-Host "→ Installing PowerShell module: $Name" -ForegroundColor Cyan
  # PS 5.1 defaults to TLS 1.0 (PSGallery rejects) and a fresh box lacks the NuGet provider.
  [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
  }
  $params = @{ Name = $Name; Force = $true; Scope = "CurrentUser"; AllowClobber = $true; Confirm = $false }
  if ($MinimumVersion) { $params.MinimumVersion = $MinimumVersion }
  Install-Module @params
}

function Ensure-PowerShellExperience {
  Install-WingetPackage -Id "junegunn.fzf"
  # ListView prediction needs PSReadLine 2.2+ (Windows PowerShell 5.1 ships 2.0); PSFzf needs fzf.
  Ensure-PSGalleryModule -Name "PSReadLine" -MinimumVersion "2.3.4"
  Ensure-PSGalleryModule -Name "PSFzf"

  $snippet = @'

# --- devbox: PSReadLine predictions + PSFzf (managed block) ---
if ((Get-Module PSReadLine).Version -ge [version]'2.2.0') {
  Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
} elseif ((Get-Module PSReadLine).Version -ge [version]'2.1.0') {
  Set-PSReadLineOption -PredictionSource History
}
if (Get-Module -ListAvailable PSFzf) {
  Import-Module PSFzf
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}
# --- end devbox block ---
'@

  $docs = [Environment]::GetFolderPath("MyDocuments")
  $targets = @(
    @{ Profile = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Exe = "powershell" }
    @{ Profile = Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1";        Exe = "pwsh" }
  )
  foreach ($t in $targets) {
    if (-not (Test-Command $t.Exe)) { continue }

    $dir = Split-Path $t.Profile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $content = if (Test-Path $t.Profile) { Get-Content $t.Profile -Raw } else { "" }
    if ($content -match "devbox: PSReadLine predictions") {
      Write-Host "✓ PSReadLine/PSFzf block already in: $($t.Profile)" -ForegroundColor Green
      continue
    }
    Write-Host "→ Adding PSReadLine/PSFzf block to: $($t.Profile)" -ForegroundColor Cyan
    Add-Content -Path $t.Profile -Value $snippet -Encoding UTF8
    Write-Host "✓ PowerShell experience configured in: $($t.Profile)" -ForegroundColor Green
  }
}

function Ensure-WezTermConfig {
  param(
    [Parameter(Mandatory=$true)]$WtConfig,
    [string]$WslDistro = "Ubuntu",   # WSL distro used by the Ubuntu launcher entry / Ctrl+Shift+3
    [bool]$MakeWslDefault = $true     # open the WSL distro by default
  )

  $resolvedFontFace = Resolve-InstalledFontFace -PreferredFontFace $WtConfig.FontFace

  # Nerd Font fallback list: resolved face first, then the configured candidates
  $faces = @($resolvedFontFace) + $WtConfig.FontFaceCandidates | Select-Object -Unique
  $fontList = ($faces | ForEach-Object { "'" + $_ + "'" }) -join ", "

  $domainLine = if ($MakeWslDefault) {
    "config.default_domain = 'WSL:$WslDistro'"
  } else {
    "-- config.default_domain left unset (opens the local Windows shell)"
  }

  # Lua string literals need backslashes doubled (D:\code -> D:\\code)
  $pwshDirLua = $WtConfig.PwshStartDir -replace '\\', '\\'

  $lua = @"
-- Managed by devbox setup-windows.ps1 — edits here are overwritten on rerun.
-- To customise permanently, change the WezTermConfig block in setup-windows.ps1.
local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

$domainLine
config.font = wezterm.font_with_fallback({ $fontList })
config.font_size = $($WtConfig.FontSize)
config.color_scheme = '$($WtConfig.ColorScheme)'
config.default_cursor_style = '$($WtConfig.CursorStyle)'
config.audible_bell = '$($WtConfig.AudibleBell)'
config.scrollback_lines = $($WtConfig.ScrollbackLines)
config.hide_tab_bar_if_only_one_tab = true
config.warn_about_missing_glyphs = false

-- On launch, open two tabs: Ubuntu (default WSL domain) + a Windows pwsh tab.
-- Swap window:spawn_tab for a split pane by replacing it with the SplitPane action.
wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:spawn_tab({
    args = { 'pwsh.exe' },
    cwd = '$pwshDirLua',
    domain = { DomainName = 'local' },
  })
end)

-- Quick shell-switching. These appear in the (+) tab-bar dropdown / launcher,
-- and Ctrl+Shift+1/2/3 spawn them directly. Ctrl+Shift+L opens the launcher.
config.launch_menu = {
  { label = 'cmd',    args = { 'cmd.exe' }, domain = { DomainName = 'local' } },
  { label = 'pwsh',   args = { 'pwsh.exe' }, cwd = '$pwshDirLua', domain = { DomainName = 'local' } },
  { label = 'Ubuntu', domain = { DomainName = 'WSL:$WslDistro' } },
}

config.keys = {
  -- Shell switching
  { key = '1', mods = 'CTRL|SHIFT', action = act.SpawnCommandInNewTab { args = { 'cmd.exe' }, domain = { DomainName = 'local' } } },
  { key = '2', mods = 'CTRL|SHIFT', action = act.SpawnCommandInNewTab { args = { 'pwsh.exe' }, cwd = '$pwshDirLua', domain = { DomainName = 'local' } } },
  { key = '3', mods = 'CTRL|SHIFT', action = act.SpawnTab { DomainName = 'WSL:$WslDistro' } },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ShowLauncher },
  -- Panes: Ctrl+Shift+D split right, Ctrl+Shift+E split down, arrows to move, Z to zoom
  { key = 'd', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'LeftArrow',  mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow',    mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow',  mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Down' },
  { key = 'z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },
}

return config
"@

  $path = Join-Path $env:USERPROFILE ".wezterm.lua"
  $desiredText = (($lua -replace "`r`n", "`n").TrimEnd()) + "`n"
  $current = if (Test-Path $path) { ((Get-Content $path -Raw) -replace "`r`n", "`n") } else { "" }

  if ($current -ne $desiredText) {
    Write-Host "→ Writing WezTerm config: $path" -ForegroundColor Cyan
    Set-Content -Path $path -Value $desiredText -Encoding UTF8 -NoNewline
    Write-Host "✓ WezTerm configured (font: $resolvedFontFace, scheme: $($WtConfig.ColorScheme))." -ForegroundColor Green
  } else {
    Write-Host "✓ WezTerm config already matches desired settings." -ForegroundColor Green
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
  # If Node is already on PATH (installed by any means), skip the winget install.
  # Re-running the MSI over an install winget doesn't track produces a 1603
  # collision. Update Node later via `winget upgrade` (or reinstall by hand).
  if (Test-Command "node") {
    Write-Host "✓ Node.js already installed ($(node --version))" -ForegroundColor Green
  } else {
    Install-WingetPackage -Id "OpenJS.NodeJS.LTS"
  }

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

# Set a per-user (persistent) environment variable, idempotently, and mirror it
# into the current session so the change takes effect without a new terminal.
function Set-UserEnvVar {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Value
  )
  $current = [System.Environment]::GetEnvironmentVariable($Name, "User")
  if ($current -eq $Value) {
    Write-Host "✓ $Name already set to $Value" -ForegroundColor Green
  } else {
    Write-Host "→ Setting $Name = $Value (User)" -ForegroundColor Cyan
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
  }
  Set-Item -Path "Env:$Name" -Value $Value   # current session
}

# Point npm/NuGet caches at the Dev Drive so package restores land on the trusted
# ReFS volume. See the DevDrivePackageCaches block in PARAMETERS.
function Ensure-DevDrivePackageCaches {
  param([Parameter(Mandatory=$true)]$Spec)

  if (-not $Spec.Configure) { return }

  $driveLetter = ($Spec.Root -split ":")[0]
  if (-not (Test-Path "$driveLetter`:\")) {
    Write-Warning "Drive $driveLetter`: not found — run bootstrap-windows.ps1 first. Skipping package-cache relocation."
    return
  }

  if ($Spec.Npm) {
    $npmCache = Join-Path $Spec.Root "npm"
    New-Item -ItemType Directory -Path $npmCache -Force | Out-Null
    Set-UserEnvVar -Name "npm_config_cache" -Value $npmCache
  }

  if ($Spec.NuGet) {
    $nugetPackages = Join-Path $Spec.Root "nuget\packages"
    $nugetHttp     = Join-Path $Spec.Root "nuget\http"
    $nugetPlugins  = Join-Path $Spec.Root "nuget\plugins"
    foreach ($d in @($nugetPackages, $nugetHttp, $nugetPlugins)) {
      New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    Set-UserEnvVar -Name "NUGET_PACKAGES"            -Value $nugetPackages
    Set-UserEnvVar -Name "NUGET_HTTP_CACHE_PATH"     -Value $nugetHttp
    Set-UserEnvVar -Name "NUGET_PLUGINS_CACHE_PATH"  -Value $nugetPlugins
  }

  Write-Host "✓ Package caches point to $($Spec.Root)" -ForegroundColor Green
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
  $existing = @((Get-MpPreference).ExclusionPath)

  $targets = [System.Collections.Generic.List[string]]::new()

  # Ubuntu (and any other Store distro) vhdx lives under its package LocalState.
  $wslDirs = Get-ChildItem -Path $packagesPath -Filter "CanonicalGroupLimited*" -Directory -ErrorAction SilentlyContinue
  if (-not $wslDirs) {
    Write-Warning "No WSL package directories found under $packagesPath. Run after WSL is installed."
  }
  foreach ($dir in $wslDirs) {
    $localState = Join-Path $dir.FullName "LocalState"
    if (Test-Path $localState) { [void]$targets.Add($localState) }
  }

  # Rancher Desktop's WSL data disk (rancher-desktop / rancher-desktop-data vhdx).
  $rdData = Join-Path $env:LOCALAPPDATA "rancher-desktop"
  if (Test-Path $rdData) { [void]$targets.Add($rdData) }

  if ($targets.Count -eq 0) {
    Write-Warning "No WSL/Rancher data directories found to exclude yet. Rerun after WSL and Rancher Desktop are installed."
    return
  }

  $added = $false
  foreach ($t in $targets) {
    if ($existing -contains $t) {
      Write-Host "✓ Defender exclusion already set: $t" -ForegroundColor Green
      continue
    }
    Write-Host "→ Adding Defender exclusion: $t" -ForegroundColor Cyan
    Add-MpPreference -ExclusionPath $t
    $added = $true
  }
  if ($added) { Write-Host "✓ WSL/Rancher directories excluded from Windows Defender." -ForegroundColor Green }
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
if ($Config.WezTermConfig.Configure) { $totalSteps++ }
if ($Config.Starship.Configure)   { $totalSteps++ }
if ($Config.ConfigurePwshExtras)  { $totalSteps++ }
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
if ($Config.InstallWezTerm)         { Install-WingetPackage -Id "wez.wezterm" }
if ($Config.InstallPowerShell7)     { Install-WingetPackage -Id "Microsoft.PowerShell" }
if ($Config.InstallVSCode)          { Install-WingetPackage -Id "Microsoft.VisualStudioCode" }
if ($Config.InstallRancherDesktop)  { Install-WingetPackage -Id "SUSE.RancherDesktop" }
if ($Config.InstallGit) {
  Install-WingetPackage -Id "Git.Git"
  if ($Config.GitConfig.Configure) { Ensure-WindowsGitConfig -GitConfig $Config.GitConfig }
}
if ($Config.InstallPowerToys)       { Install-WingetPackage -Id "Microsoft.PowerToys" }
if ($Config.Install7Zip)            { Install-WingetPackage -Id "7zip.7zip" }
if ($Config.InstallNode)            { Ensure-NodeAndNcu }
if ($Config.InstallAzureFunctionsCoreTools) { Install-WingetPackage -Id "Microsoft.Azure.FunctionsCoreTools" }

if ($Config.Fonts.Count -gt 0) {
  Show-Progress "Installing fonts"
  foreach ($font in $Config.Fonts) {
    if (
      $Config.WezTermConfig.Configure -and
      $font -eq $Config.WezTermConfig.FontPackageId -and
      $Config.WezTermConfig.FontFaceCandidates.Count -gt 0 -and
      $Config.WezTermConfig.FontDownloadUrl
    ) {
      Install-NerdFontArchive `
        -PackageId $font `
        -DownloadUrl $Config.WezTermConfig.FontDownloadUrl `
        -FontFaces $Config.WezTermConfig.FontFaceCandidates `
        -ArchiveFilter $Config.WezTermConfig.FontArchiveFilter | Out-Null
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

if ($Config.WezTermConfig.Configure) {
  Show-Progress "Configuring WezTerm"
  Ensure-WezTermConfig -WtConfig $Config.WezTermConfig `
    -WslDistro $Config.UbuntuDistroName `
    -MakeWslDefault $Config.SetWslAsDefaultInWezTerm
}

if ($Config.Starship.Configure) {
  Show-Progress "Configuring Starship"
  Ensure-StarshipPowerShell -Preset $Config.Starship.Preset
}

if ($Config.ConfigurePwshExtras) {
  Show-Progress "Configuring PowerShell experience (fzf + PSReadLine)"
  Ensure-PowerShellExperience
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
if ($Config.DevDrivePackageCaches.Configure) { Ensure-DevDrivePackageCaches -Spec $Config.DevDrivePackageCaches }

Write-Progress -Activity "devbox setup" -Completed
Write-Host "`nDone." -ForegroundColor Green
Write-Host "Tip: Apply WSL resource changes with: wsl --shutdown" -ForegroundColor Cyan
Write-Host "Tip: Restart Rancher Desktop to apply VM resource changes." -ForegroundColor Cyan
