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
    UseDelta        = $true    # core.pager + interactive.diffFilter, matching ensure_delta on Ubuntu
  }
  Install7Zip            = $true
  InstallNode            = $true   # host Node via fnm (per-project versions; see Ensure-Node)
  NodeMajorVersion       = 24      # fnm default — keep in step with NODE_MAJOR_VERSION in setup-ubuntu.sh
  NpmGlobalPrefix        = $null   # npm -g target shared by every Node version; $null = %APPDATA%\npm
  MigrateLegacyNode      = "ask"   # ask | yes | no — move off the Node MSI / nvm-windows (see Ensure-Node)
  InstallAzureFunctionsCoreTools = $true   # `func` CLI via winget (self-updates on `winget upgrade`)
  InstallAspire          = $true   # `aspire` CLI via winget (Microsoft.Aspire). Self-contained binary —
                                   # a .NET SDK is only needed to build/run an AppHost, not to install it.

  # Agentic CLIs. Both are native builds (Codex's winget package is the Rust
  # binary, not the npm JS wrapper), so neither carries a Node dependency. They
  # differ in how they stay current: Claude Code comes from Anthropic's own
  # installer and updates itself in the background (see Ensure-ClaudeCode), so it
  # is the one app here outside winget; Codex has no self-updater and rides
  # `winget upgrade --all` in update-windows.ps1 like every other app.
  InstallClaudeCode      = $true   # `claude` — native install, self-updating
  InstallCodex           = $true   # `codex`  — OpenAI.Codex

  # Starship — cross-shell prompt engine; configures PowerShell profiles for PS5 and PS7
  Starship = @{
    Configure = $true
    Preset    = "nerd-font-symbols"   # `starship preset --list`; "" keeps starship's built-in default
  }

  # PowerShell experience — fzf + PSFzf (Ctrl+T / Ctrl+R) and PSReadLine predictive IntelliSense
  ConfigurePwshExtras = $true

  # Report the current directory as the shell's title, so terminals that label a
  # tab with it (Windows Terminal, VS Code) show the directory instead of the
  # profile name. Rides on Starship's pre-command hook, so it needs Starship above.
  ShowCwdInTabTitle = $true

  # Modern CLI tools — the Windows half of what setup-ubuntu.sh installs, so a
  # pwsh shell on the host has the same basics as the WSL one. Listed here rather
  # than as individual Install* switches because they are all plain binaries that
  # work the moment they are on PATH; zoxide and eza are deliberately absent, as
  # both need a managed profile block to be useful.
  CliTools = @(
    "BurntSushi.ripgrep.MSVC",   # rg
    "sharkdp.bat",               # bat
    "sharkdp.fd",                # fd
    "jqlang.jq",                 # jq
    "dandavison.delta",          # git-delta — wired into git by GitConfig.UseDelta
    "JesseDuffield.lazygit",     # lazygit
    "GitHub.cli"                 # gh
  )

  # Fonts (winget IDs)
  Fonts = @(
    "Microsoft.CascadiaCode",
    "NERD-Fonts.JetBrainsMono"
  )

  # Cloud CLIs (remove any you don't need; add Amazon.AWSCLI / Google.CloudSDK if multi-cloud).
  # Azd provisions and deploys an Aspire AppHost; kubelogin is the Entra ID
  # credential plugin kubectl shells out to — an Entra-integrated AKS cluster
  # writes `exec: kubelogin` into the kubeconfig, so kubectl alone cannot log in.
  CloudCLIs = @(
    "Microsoft.AzureCLI",
    "Microsoft.Azd",
    "Microsoft.Azure.Kubelogin"
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
    TabTitleShowCwd    = $true   # tab titles show the pane's current directory, not the program name
    TabMaxWidth        = 28      # tab title width before truncation (WezTerm default is 16)
    # Quick shell-switching: the (+) tab-bar dropdown lists these, and Ctrl+Shift+1/2
    # spawn pwsh / Ubuntu directly. Ctrl+Shift+L opens the launcher menu.
    # Splits are Ctrl+Shift+Alt+<arrow> and inherit the pane's domain and cwd.
    PwshStartDir       = "D:\code"       # pwsh (Ctrl+Shift+1) opens here
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

function Set-ManagedProfileBlock {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Marker,   # text after "devbox: " in the opening comment
    [Parameter(Mandatory=$true)][string]$Snippet,
    [Parameter(Mandatory=$true)][string]$Label
  )
  # Rewrites the block in place rather than only appending when absent: profiles
  # written by an earlier run already carry the marker, so an append-only check
  # silently strands them on the old block whenever this snippet changes.
  $dir = Split-Path $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

  $block = $Snippet.Trim()
  $content = if (Test-Path $Path) { Get-Content $Path -Raw } else { "" }
  $pattern = "(?ms)^# --- devbox: $([regex]::Escape($Marker)).*?^# --- end devbox block ---"

  if ($content -match $pattern) {
    if ($Matches[0].Trim() -eq $block) {
      Write-Host "✓ $Label block already current in: $Path" -ForegroundColor Green
      return
    }
    Write-Host "→ Updating $Label block in: $Path" -ForegroundColor Cyan
    # MatchEvaluator, not a replacement string — the snippet contains $ and \ that
    # -replace would treat as capture-group references.
    $updated = [regex]::Replace($content, $pattern, { param($m) $block })
    Set-Content -Path $Path -Value $updated.TrimEnd() -Encoding UTF8
  } else {
    Write-Host "→ Adding $Label block to: $Path" -ForegroundColor Cyan
    Add-Content -Path $Path -Value "`r`n$block" -Encoding UTF8
  }
  Write-Host "✓ $Label configured in: $Path" -ForegroundColor Green
}

function Get-PowerShellProfileTargets {
  $docs = [Environment]::GetFolderPath("MyDocuments")
  @(
    @{ Profile = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Exe = "powershell" }
    @{ Profile = Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1";        Exe = "pwsh" }
  ) | Where-Object { Test-Command $_.Exe }
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
# PSReadLine's defaults lean on DarkGray and dim ANSI, which all but vanish on
# the OneHalfDark background — script parameters and their arguments worst of
# all. Re-map the syntax tokens onto the OneHalfDark palette. Scoped in & { }
# so $e stays out of the session, and built from [char]27 rather than `e
# because the `e escape is PowerShell 6+ only and this profile also runs on 5.1.
& {
  $e = [char]27
  $colors = @{
    Command   = "$e[38;2;97;175;239m"    # #61afef blue   — cmdlets, scripts, .\foo.ps1
    Parameter = "$e[38;2;86;182;194m"    # #56b6c2 cyan   — -Switch names
    Variable  = "$e[38;2;224;108;117m"   # #e06c75 red
    String    = "$e[38;2;152;195;121m"   # #98c379 green
    Number    = "$e[38;2;209;154;102m"   # #d19a66 orange
    Type      = "$e[38;2;229;192;123m"   # #e5c07b yellow
    Keyword   = "$e[38;2;198;120;221m"   # #c678dd magenta
    Operator  = "$e[38;2;171;178;191m"   # #abb2bf foreground
    Member    = "$e[38;2;220;223;228m"   # #dcdfe4 bright foreground
    Default   = "$e[38;2;220;223;228m"   # bare arguments, paths
    Comment   = "$e[38;2;127;132;142m"   # #7f848e — deliberately quiet
  }
  # InlinePrediction arrived in PSReadLine 2.1; the 2.0 that ships in-box with
  # Windows PowerShell 5.1 throws "not a valid color property" on it.
  if ((Get-Module PSReadLine).Version -ge [version]'2.1.0') {
    $colors.InlinePrediction = "$e[38;2;92;99;112m"   # #5c6370 — dimmer than any real token
  }
  Set-PSReadLineOption -Colors $colors
}
if (Get-Module -ListAvailable PSFzf) {
  Import-Module PSFzf
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}
# --- end devbox block ---
'@

  foreach ($t in Get-PowerShellProfileTargets) {
    Set-ManagedProfileBlock -Path $t.Profile -Marker "PSReadLine predictions" `
      -Snippet $snippet -Label "PSReadLine/PSFzf"
  }
}

function Ensure-WezTermConfig {
  param(
    [Parameter(Mandatory=$true)]$WtConfig,
    [string]$WslDistro = "Ubuntu",   # WSL distro used by the Ubuntu launcher entry / Ctrl+Shift+2
    [bool]$MakeWslDefault = $true,    # open the WSL distro by default
    [bool]$UsePwsh = $true            # local-domain panes run pwsh instead of WezTerm's cmd.exe default
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

  # Tab titles. Literal here-string: the Lua below contains $ and \ that must survive verbatim.
  # WezTerm's local-domain default on Windows is %COMSPEC%, i.e. cmd.exe — so a
  # pane split off a pwsh pane would come up in cmd unless default_prog says
  # otherwise. Only set when setup actually installs pwsh: pointing default_prog
  # at a missing binary would break the local domain outright.
  $defaultProgLine = if ($UsePwsh) {
    "config.default_prog = { 'pwsh.exe' }"
  } else {
    "-- config.default_prog left unset (local panes use %COMSPEC%, normally cmd.exe)"
  }

  $tabTitleLua = "-- Tab titles left at the WezTerm default (the program/shell title)."
  if ($WtConfig.TabTitleShowCwd) {
    $tabTitleLua = @'
-- Tab titles show the active pane's current directory instead of the program
-- name. Both Windows and WSL panes report their cwd as OSC 7, from the managed
-- Invoke-Starship-PreCommand block setup-windows.ps1 writes and the .bashrc/.zshrc
-- block setup-ubuntu.sh installs. A Windows path on a WSL pane is wsl.exe's own
-- cwd, not the shell's, so it is ignored and the pane title is used instead.
local function pane_dir(pane)
  local cwd = pane.current_working_dir
  if not cwd then return nil end
  local path
  if type(cwd) == 'string' then
    path = (cwd:gsub('^file://[^/]*', ''))   -- older WezTerm: a file:// URL string
  else
    path = cwd.file_path or cwd.path         -- newer WezTerm: a Url object
  end
  if not path or path == '' then return nil end
  local domain = pane.domain_name or 'local'
  if domain ~= 'local' and path:match('^/?%a:') then return nil end
  path = path:gsub('\\', '/'):gsub('/+', '/'):gsub('(.)/+$', '%1')
  return path:match('[^/]+$') or path
end

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane
  local domain = pane.domain_name or 'local'
  local title = pane_dir(pane) or pane.title
  if domain ~= 'local' then
    title = domain:gsub('^WSL:', '') .. ': ' .. title   -- keep Ubuntu tabs distinct from Windows ones
  end
  return wezterm.truncate_right(' ' .. (tab.tab_index + 1) .. ': ' .. title .. ' ', max_width)
end)
'@
  }

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
config.tab_max_width = $($WtConfig.TabMaxWidth)

$defaultProgLine

$tabTitleLua

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
-- and Ctrl+Shift+1/2 spawn them directly. Ctrl+Shift+L opens the launcher.
-- No cmd entry: default_prog above makes pwsh the local shell, and cmd is still
-- one `cmd` away inside it.
config.launch_menu = {
  { label = 'pwsh',   args = { 'pwsh.exe' }, cwd = '$pwshDirLua', domain = { DomainName = 'local' } },
  { label = 'Ubuntu', domain = { DomainName = 'WSL:$WslDistro' } },
}

config.keys = {
  -- Shell switching
  { key = '1', mods = 'CTRL|SHIFT', action = act.SpawnCommandInNewTab { args = { 'pwsh.exe' }, cwd = '$pwshDirLua', domain = { DomainName = 'local' } } },
  { key = '2', mods = 'CTRL|SHIFT', action = act.SpawnTab { DomainName = 'WSL:$WslDistro' } },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ShowLauncher },

  -- Splits: Ctrl+Shift+Alt+<arrow>, in every direction. SplitPane takes a
  -- direction, unlike the legacy SplitHorizontal/SplitVertical actions that can
  -- only ever split right and down. The new pane inherits the current pane's
  -- domain and cwd, so one binding covers a pwsh pane and a WSL pane alike —
  -- no `wezterm cli split-pane --cwd ...` from either side.
  { key = 'LeftArrow',  mods = 'CTRL|SHIFT|ALT', action = act.SplitPane { direction = 'Left' } },
  { key = 'RightArrow', mods = 'CTRL|SHIFT|ALT', action = act.SplitPane { direction = 'Right' } },
  { key = 'UpArrow',    mods = 'CTRL|SHIFT|ALT', action = act.SplitPane { direction = 'Up' } },
  { key = 'DownArrow',  mods = 'CTRL|SHIFT|ALT', action = act.SplitPane { direction = 'Down' } },
  -- Kept for muscle memory: split right / split down.
  { key = 'd', mods = 'CTRL|SHIFT', action = act.SplitPane { direction = 'Right' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitPane { direction = 'Down' } },

  -- Ctrl+Shift+<arrow> moves between panes, Z zooms one to fill the tab
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

function Ensure-ShellTabTitle {
  # Windows Terminal and the VS Code terminal label a tab with whatever title the
  # shell reports, and PowerShell reports none — hence tabs that read "PowerShell".
  # Invoke-Starship-PreCommand is Starship's supported per-prompt hook, so this
  # needs no prompt wrapping and survives Starship regenerating its init.
  $snippet = @'

# --- devbox: tab title = current directory (managed block) ---
function Invoke-Starship-PreCommand {
  $loc = $null
  try { $loc = Get-Location } catch { return }
  try {
    $leaf = Split-Path -Leaf $loc.Path
    if ($leaf) { $Host.UI.RawUI.WindowTitle = $leaf }
  } catch { }   # hosts with no console (ISE, redirected output) can't set a title
  # OSC 7 reports the cwd itself, which is what WezTerm inherits when a pane is
  # split. Without it WezTerm falls back to inspecting the shell's process, which
  # it cannot do reliably for pwsh, and a new pane opens in the wrong directory.
  # The bash/zsh counterpart is __devbox_term_cwd in setup-ubuntu.sh.
  try {
    if ($loc.Provider.Name -eq 'FileSystem') {
      $url = ([uri]::new($loc.ProviderPath).AbsoluteUri) -replace '^file:///', "file://$env:COMPUTERNAME/"
      $esc = [char]27
      Write-Host -NoNewline "$esc]7;$url$esc\"
    }
  } catch { }   # non-filesystem providers (Cert:, HKLM:) have no meaningful URL
}
# --- end devbox block ---
'@

  foreach ($t in Get-PowerShellProfileTargets) {
    Set-ManagedProfileBlock -Path $t.Profile -Marker "tab title" `
      -Snippet $snippet -Label "Tab-title"
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

# Claude Code, from Anthropic's own installer rather than winget — the one app in
# this script that lives outside the winget inventory. The native install lands in
# ~/.local/bin and updates itself in the background, which is upstream's
# recommended path and the one setup-ubuntu.sh already takes. The winget package
# does not auto-update, and the CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE opt-in
# that made it try cannot replace a running claude.exe (Windows locks it) — which
# is exactly when a new release lands, mid-session.
#
# Unlike everything else here this install is per-user, not machine-wide: it
# follows the profile of whoever this elevated script runs as, the same as the
# ~/.wezterm.lua and profile blocks written further down.
function Ensure-ClaudeCode {
  # Migrate machines set up before this switch. Two claude.exe on one PATH means
  # the winner is whichever directory comes first, and only the native one can
  # update itself — the same reason ensure_claude_code drops the superseded npm
  # global on the Ubuntu side.
  # Held in a variable rather than passed as a quoted literal: audit-windows.ps1
  # scrapes quoted package ids out of this script as the set setup *installs*, and
  # this is the one place that names a package in order to remove it instead.
  $staleWingetId = "Anthropic.ClaudeCode"
  $wingetList = winget list --id $staleWingetId --exact --accept-source-agreements 2>$null | Out-String
  if ($wingetList -match [regex]::Escape($staleWingetId)) {
    Write-Host "→ Removing the winget Claude Code (superseded by the native install)" -ForegroundColor Cyan
    winget uninstall --id $staleWingetId --exact --silent --disable-interactivity 2>&1 | Out-Null
  }

  # Refresh PATH before the check: the winget uninstall above may have just
  # removed the claude.exe this session still has cached on its PATH.
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path", "User")

  if (Test-Command "claude") {
    $ver = (claude --version 2>$null | Select-Object -First 1)
    Write-Host "✓ Claude Code already installed ($ver) — it self-updates" -ForegroundColor Green
    return
  }

  Write-Host "→ Installing Claude Code (native installer)" -ForegroundColor Cyan
  # Run the installer in a child process rather than `irm … | iex`: this script
  # sets Set-StrictMode -Version Latest and $ErrorActionPreference = "Stop" for
  # the whole session, and an upstream script written without those assumptions
  # aborts on the first error it would otherwise shrug off.
  $installer = Join-Path $env:TEMP "claude-install.ps1"
  Invoke-WebRequest -Uri "https://claude.ai/install.ps1" -OutFile $installer -UseBasicParsing
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
  Remove-Item $installer -ErrorAction SilentlyContinue

  # The installer appends ~/.local/bin to the *user* PATH; pick that up so the
  # rest of this run (and the audit hint below) sees `claude`.
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path", "User")
  if (Test-Command "claude") {
    Write-Host "✓ Claude Code installed — run 'claude' to sign in" -ForegroundColor Green
  } else {
    Write-Warning "Claude Code installed, but 'claude' is not on PATH in this session. Open a new terminal and run: claude"
  }
}

# Node comes from fnm, as on the WSL side (ensure_node): client repos pin their own
# Node (.nvmrc / .node-version / package.json engines) and fnm switches on `cd`.
# NodeMajorVersion is only the default. Versions install side by side, so bumping
# the pin and rerunning adds the new major; moving the default onto it is reported,
# not done, since every shell outside a pinned project would change underneath you.
#
# npm globals go to one prefix shared by every version. fnm gives each version its
# own, so globals would otherwise vanish on every patch update and inside any
# project that selects another Node. %APPDATA%\npm is where the Node MSI put them,
# so globals from an MSI-era install carry straight over.
function Ensure-Node {
  param(
    [Parameter(Mandatory=$true)][int]$MajorVersion,
    [string]$NpmGlobalPrefix,
    [ValidateSet("ask", "yes", "no")][string]$MigrateLegacy = "ask"
  )
  if (-not $NpmGlobalPrefix) { $NpmGlobalPrefix = Join-Path $env:APPDATA "npm" }

  Install-WingetPackage -Id "Schniz.fnm"
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path", "User")
  if (-not (Test-Command "fnm")) {
    Write-Warning "fnm not on PATH after install. Open a new terminal and rerun setup."
    return
  }

  $snippet = @'

# --- devbox: fnm (managed block) ---
# Node version manager. --use-on-cd switches Node on entering a directory that
# carries .nvmrc / .node-version / package.json engines; elsewhere the fnm default
# applies. The bash/zsh counterpart is the "devbox: fnm" block in setup-ubuntu.sh.
if (Get-Command fnm -ErrorAction SilentlyContinue) {
  fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}
# --- end devbox block ---
'@
  foreach ($t in Get-PowerShellProfileTargets) {
    Set-ManagedProfileBlock -Path $t.Profile -Marker "fnm" -Snippet $snippet -Label "fnm"
  }

  # This session is not a profile-loaded shell, so activate fnm here too.
  fnm env --shell powershell | Out-String | Invoke-Expression

  if (@(fnm list) -match "^\* v$MajorVersion\.") {
    Write-Host "✓ node $MajorVersion.x already installed (fnm)" -ForegroundColor Green
  } else {
    Write-Host "→ Installing Node.js $MajorVersion.x (fnm)" -ForegroundColor Cyan
    fnm install $MajorVersion
    if ($LASTEXITCODE -ne 0) { throw "fnm install $MajorVersion failed (exit $LASTEXITCODE)" }
  }

  # `fnm install` makes the first version it installs the default; after that the
  # default only moves when asked.
  $default = @(fnm list) | ForEach-Object { if ($_ -match '(v\d+\.\d+\.\d+).*\bdefault\b') { $Matches[1] } } | Select-Object -First 1
  if (-not $default) {
    Write-Host "→ Setting fnm default to $MajorVersion.x" -ForegroundColor Cyan
    fnm default $MajorVersion
  } elseif ($default -like "v$MajorVersion.*") {
    Write-Host "✓ fnm default is $default" -ForegroundColor Green
  } else {
    Write-Warning "fnm default is $default, pin is $MajorVersion.x — move it with: fnm default $MajorVersion"
  }
  # Re-evaluate: the multishell link made above predates any default.
  fnm env --shell powershell | Out-String | Invoke-Expression

  # Read from ~/.npmrc: npm refuses `npm config get prefix` ("protected").
  $npmrc = Join-Path $env:USERPROFILE ".npmrc"
  $prefixLine = "prefix=$NpmGlobalPrefix"
  if ((Test-Path $npmrc) -and (@(Get-Content $npmrc) -contains $prefixLine)) {
    Write-Host "✓ npm global prefix is $NpmGlobalPrefix" -ForegroundColor Green
  } else {
    Write-Host "→ Setting npm global prefix to $NpmGlobalPrefix (~/.npmrc)" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $NpmGlobalPrefix -Force | Out-Null
    npm config set prefix $NpmGlobalPrefix
  }
  # On Windows the global bin directory IS the prefix. The MSI put it on the user
  # PATH; a machine that never had the MSI needs it added.
  $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
  if (@($userPath -split ';') -contains $NpmGlobalPrefix) {
    Write-Host "✓ $NpmGlobalPrefix already on user PATH" -ForegroundColor Green
  } else {
    Write-Host "→ Adding $NpmGlobalPrefix to user PATH" -ForegroundColor Cyan
    [System.Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(';') + ";$NpmGlobalPrefix"), "User")
    $env:Path += ";$NpmGlobalPrefix"
  }

  # Earlier Node installs fnm supersedes. Both put node.exe on the machine PATH,
  # which WSL inherits through interop, so a leftover one also leaks into every
  # Linux shell. Each removal asks first (MigrateLegacy); the audit reports
  # whatever is left. MSI-era globals need no moving — %APPDATA%\npm is already
  # the shared prefix — but nvm-windows keeps its globals inside each version.
  $confirm = {
    param([string]$Question)
    switch ($MigrateLegacy) {
      "yes" { return $true }
      "no"  { Write-Host "  skipped (MigrateLegacyNode = no)"; return $false }
    }
    if ([Console]::IsInputRedirected) {
      Write-Warning "No terminal to prompt on — skipped (set MigrateLegacyNode = 'yes' to run unattended)"
      return $false
    }
    $reply = Read-Host "  $Question [y/N]"
    if ($reply -match '^[yY]$') { return $true }
    Write-Host "  skipped"
    return $false
  }

  if ($env:NVM_HOME) {
    $nvmModules = if ($env:NVM_SYMLINK) { Join-Path $env:NVM_SYMLINK "node_modules" } else { $null }
    $nvmGlobals = @()
    if ($nvmModules -and (Test-Path $nvmModules)) {
      foreach ($d in Get-ChildItem $nvmModules -Directory) {
        if ($d.Name -in @("npm", "corepack")) { continue }
        if ($d.Name.StartsWith("@")) {
          $nvmGlobals += Get-ChildItem $d.FullName -Directory | ForEach-Object { "$($d.Name)/$($_.Name)" }
        } else { $nvmGlobals += $d.Name }
      }
    }
    Write-Host "→ nvm-windows still installed ($env:NVM_HOME)$(if ($nvmGlobals) { "; its globals: $($nvmGlobals -join ' ')" })" -ForegroundColor Cyan
    if (& $confirm "Reinstall its globals under fnm and uninstall nvm-windows?") {
      foreach ($g in $nvmGlobals) {
        if (-not (Test-Path (Join-Path $NpmGlobalPrefix "node_modules\$g"))) { npm install -g $g }
      }
      winget uninstall --id CoreyButler.NVMforWindows -e --silent --disable-interactivity
      Write-Host "✓ nvm-windows removed — open a new terminal to drop it from PATH" -ForegroundColor Green
    }
  }

  if (Test-Path (Join-Path $env:ProgramFiles "nodejs\node.exe")) {
    $msiIds = @("OpenJS.NodeJS.LTS", "OpenJS.NodeJS") | Where-Object {
      (winget list --id $_ -e --accept-source-agreements 2>$null | Out-String) -match [regex]::Escape($_)
    }
    Write-Host "→ The Node.js MSI is still installed alongside fnm ($env:ProgramFiles\nodejs)" -ForegroundColor Cyan
    if (-not $msiIds) {
      Write-Warning "winget does not track it — remove it from Settings → Apps → Installed apps"
    } elseif (& $confirm "Uninstall it ($($msiIds -join ', '))? Globals in $NpmGlobalPrefix stay.") {
      foreach ($id in $msiIds) { winget uninstall --id $id -e --silent --disable-interactivity }
      Write-Host "✓ Node.js MSI removed" -ForegroundColor Green
    }
  }

  # Keep the `npm install -g` call below literal, not built from a variable —
  # audit-windows.ps1 regexes it out as the expected set of npm globals.
  if (Test-Path (Join-Path $NpmGlobalPrefix "node_modules\npm-check-updates")) {
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
  # winget has just put git (and delta) on the machine PATH, but this session's
  # copy predates that — refresh before probing for either.
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path", "User")
  if (-not (Test-Command "git")) {
    Write-Warning "git not in PATH yet — open a new terminal after installation and rerun to apply git config."
    return
  }
  Ensure-GitSetting "core.autocrlf"        $GitConfig.AutoCRLF
  Ensure-GitSetting "init.defaultBranch"   $GitConfig.DefaultBranch
  Ensure-GitSetting "pull.rebase"          $GitConfig.PullRebase
  Ensure-GitSetting "push.autoSetupRemote" $GitConfig.AutoSetupRemote
  # Same three keys ensure_delta sets on the Ubuntu side, so `git diff` reads the
  # same in either shell. Skipped unless delta is actually on PATH — setting
  # core.pager to a missing binary breaks every paged git command.
  if ($GitConfig.UseDelta) {
    if (Test-Command "delta") {
      Ensure-GitSetting "core.pager"            "delta"
      Ensure-GitSetting "interactive.diffFilter" "delta --color-only"
      Ensure-GitSetting "delta.navigate"         "true"
    } else {
      Write-Warning "delta not in PATH yet — rerun after installation to wire it into git."
    }
  }
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
if ($Config.ShowCwdInTabTitle)    { $totalSteps++ }
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
if ($Config.InstallPowerToys)       { Install-WingetPackage -Id "Microsoft.PowerToys" }
if ($Config.Install7Zip)            { Install-WingetPackage -Id "7zip.7zip" }
foreach ($tool in $Config.CliTools) { Install-WingetPackage -Id $tool }
# After the CLI tools: Ensure-WindowsGitConfig wires delta into git, so delta has
# to be installed by the time it runs.
if ($Config.InstallGit) {
  Install-WingetPackage -Id "Git.Git"
  if ($Config.GitConfig.Configure) { Ensure-WindowsGitConfig -GitConfig $Config.GitConfig }
}
if ($Config.InstallNode)            { Ensure-Node -MajorVersion $Config.NodeMajorVersion -NpmGlobalPrefix $Config.NpmGlobalPrefix -MigrateLegacy $Config.MigrateLegacyNode }
if ($Config.InstallAzureFunctionsCoreTools) { Install-WingetPackage -Id "Microsoft.Azure.FunctionsCoreTools" }
if ($Config.InstallAspire)           { Install-WingetPackage -Id "Microsoft.Aspire" }
if ($Config.InstallClaudeCode)      { Ensure-ClaudeCode }
if ($Config.InstallCodex)           { Install-WingetPackage -Id "OpenAI.Codex" }

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
    -MakeWslDefault $Config.SetWslAsDefaultInWezTerm `
    -UsePwsh $Config.InstallPowerShell7
}

if ($Config.Starship.Configure) {
  Show-Progress "Configuring Starship"
  Ensure-StarshipPowerShell -Preset $Config.Starship.Preset
}

if ($Config.ConfigurePwshExtras) {
  Show-Progress "Configuring PowerShell experience (fzf + PSReadLine)"
  Ensure-PowerShellExperience
}

if ($Config.ShowCwdInTabTitle) {
  Show-Progress "Configuring tab titles (current directory)"
  Ensure-ShellTabTitle
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
