# =========================
# PARAMETERS (edit these)
# =========================
#
# Read-only DRIFT AUDIT for the Windows host. Compares the current machine against
# what setup-windows.ps1 / update-windows.ps1 would install and configure, and
# reports where they diverge. It changes NOTHING — every finding comes with a
# two-way reconcile hint: how to fix the drift, and (for unexpected apps) how to
# adopt it into setup so the report doubles as a setup-update worklist.
#
# "Expected" state is parsed straight out of the setup scripts (winget -Id calls,
# the $Config arrays, git/profile/cache settings) so this audit can never drift
# from setup itself.

$Config = @{
  SetupScript  = Join-Path $PSScriptRoot "setup-windows.ps1"
  UpdateScript = Join-Path $PSScriptRoot "update-windows.ps1"

  CheckApps        = $true   # winget-managed apps: installed-not-in-setup + missing
  CheckVSCodeExts  = $true   # code --list-extensions vs $Config.VSCodeExtensions
  CheckNpmGlobals  = $true   # npm -g globals vs the ones setup installs
  CheckConfigFiles = $true   # WezTerm, PowerShell profiles, .wslconfig, cache env vars, git
  CheckStartup     = $true   # devbox-managed startup (Dev Drive task, ssh-agent) + autostart inventory
}

# =========================
# IMPLEMENTATION
# =========================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:driftCount = 0

function Write-Section { param([string]$Title) Write-Host "`n=== $Title ===" -ForegroundColor White }
function Report-Ok    { param([string]$Msg) Write-Host "✓ $Msg" -ForegroundColor Green }
function Report-Warn  { param([string]$Msg) Write-Host "⚠ $Msg" -ForegroundColor Yellow }
# Inventory line — visibility only, never counted as drift.
function Report-Info  { param([string]$Msg) Write-Host "· $Msg" -ForegroundColor DarkGray }
function Report-Drift {
  param([string]$Msg, [string[]]$Fix)
  $script:driftCount++
  Write-Host "⚠ $Msg" -ForegroundColor Yellow
  foreach ($f in $Fix) { Write-Host "    $f" -ForegroundColor DarkGray }
}

# Extract the top-level `$Config = @{ ... }` hashtable literal from a setup script
# WITHOUT executing the script. The right-hand side is pure data (strings/bools/
# arrays/nested hashtables), so invoking just that literal in a fresh scope is safe.
function Get-SetupConfig {
  param([string]$Path)
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
  $assign = $ast.Find({
    param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left.Extent.Text -eq '$Config'
  }, $false)
  if (-not $assign) { throw "Could not locate `$Config in $Path" }
  return & ([scriptblock]::Create($assign.Right.Extent.Text))
}

# The managed profile block a given Ensure-* function writes, lifted out of the
# setup script's here-string. Lets the audit spot a block that is present but
# stale — the case a marker-only check misses entirely.
function Get-ManagedBlockText {
  param([string]$Path, [string]$FunctionName)
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
  $func = $ast.Find({
    param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $FunctionName
  }, $true)
  if (-not $func) { return $null }
  $str = $func.Find({
    param($n)
    $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
    $n.Value -match 'end devbox block'
  }, $true)
  if ($str) { return $str.Value.Trim() }
  return $null
}

# All literal winget IDs installed by the given scripts (Install-WingetPackage -Id "…").
function Get-LiteralWingetIds {
  param([string[]]$Paths)
  $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $Paths) {
    if (-not (Test-Path $p)) { continue }
    foreach ($m in [regex]::Matches((Get-Content $p -Raw), '-Id\s+"([^"]+)"')) {
      [void]$ids.Add($m.Groups[1].Value)
    }
  }
  return ,$ids   # comma stops PowerShell enumerating the HashSet into an array
}

# npm packages setup installs globally (npm install -g <name>).
function Get-ExpectedNpmGlobals {
  param([string[]]$Paths)
  $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $Paths) {
    if (-not (Test-Path $p)) { continue }
    foreach ($m in [regex]::Matches((Get-Content $p -Raw), 'npm\s+install\s+-g\s+([\w@\/.-]+)')) {
      [void]$names.Add($m.Groups[1].Value)
    }
  }
  return ,$names   # comma stops PowerShell enumerating the HashSet into an array
}

function Test-Command($Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# --- load expected state ---
if (-not (Test-Path $Config.SetupScript)) { throw "setup script not found: $($Config.SetupScript)" }
$setup   = Get-SetupConfig -Path $Config.SetupScript
$scripts = @($Config.SetupScript, $Config.UpdateScript)

Write-Host "devbox drift audit (Windows)" -ForegroundColor Cyan
Write-Host "Comparing this machine against $(Split-Path $Config.SetupScript -Leaf) + $(Split-Path $Config.UpdateScript -Leaf)" -ForegroundColor DarkGray

# ---------- Apps (winget) ----------
if ($Config.CheckApps) {
  Write-Section "winget apps"
  if (-not (Test-Command "winget")) {
    Report-Warn "winget not available — skipping app drift."
  } else {
    $expected = Get-LiteralWingetIds -Paths $scripts
    foreach ($f in @($setup.Fonts) + @($setup.CloudCLIs)) { if ($f) { [void]$expected.Add($f) } }

    $tmp = Join-Path $env:TEMP "devbox-winget-export.json"
    winget export -o $tmp --accept-source-agreements --disable-interactivity 2>$null | Out-Null
    $installed = @()
    if (Test-Path $tmp) {
      $json = Get-Content $tmp -Raw | ConvertFrom-Json
      $installed = @($json.Sources | ForEach-Object { $_.Packages.PackageIdentifier }) | Where-Object { $_ }
      Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    $installedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$installed, [System.StringComparer]::OrdinalIgnoreCase)

    $missing = @($expected) | Where-Object { -not $installedSet.Contains($_) }
    $extra   = @($installed | Sort-Object -Unique) | Where-Object { -not $expected.Contains($_) }

    foreach ($id in $missing) {
      Report-Drift "Missing (setup installs it, not present): $id" @(
        "install: winget install --id $id -e",
        "or rerun: .\setup-windows.ps1"
      )
    }
    foreach ($id in $extra) {
      Report-Drift "Extra (installed, not in setup): $id" @(
        "remove:  winget uninstall --id $id",
        "adopt:   add `"$id`" to a `$Config array (Fonts/CloudCLIs) or an Install-WingetPackage -Id line in setup-windows.ps1"
      )
    }
    if (-not $missing -and -not $extra) { Report-Ok "winget apps match setup ($($expected.Count) expected)." }
  }
}

# ---------- VS Code extensions ----------
if ($Config.CheckVSCodeExts) {
  Write-Section "VS Code extensions"
  if (-not (Test-Command "code")) {
    Report-Warn "'code' not on PATH — skipping extension drift."
  } else {
    $expected = @($setup.VSCodeExtensions)
    $installed = @(code --list-extensions 2>$null)
    $expSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$expected, [System.StringComparer]::OrdinalIgnoreCase)
    $insSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$installed, [System.StringComparer]::OrdinalIgnoreCase)

    $missingExt = @($expected  | Where-Object { -not $insSet.Contains($_) })
    $extraExt   = @($installed | Where-Object { -not $expSet.Contains($_) })
    foreach ($e in $missingExt) {
      Report-Drift "Missing extension: $e" @("install: code --install-extension $e")
    }
    foreach ($i in $extraExt) {
      Report-Drift "Extra extension (not in setup): $i" @(
        "remove: code --uninstall-extension $i",
        "adopt:  add `"$i`" to `$Config.VSCodeExtensions in setup-windows.ps1"
      )
    }
    if ($missingExt.Count -eq 0 -and $extraExt.Count -eq 0) {
      Report-Ok "VS Code extensions match setup."
    }
  }
}

# ---------- npm globals ----------
if ($Config.CheckNpmGlobals) {
  Write-Section "npm -g globals"
  if (-not (Test-Command "npm")) {
    Report-Warn "npm not on PATH — skipping npm global drift."
  } else {
    $expected = Get-ExpectedNpmGlobals -Paths $scripts
    $globals = @()
    try {
      $lsJson = npm ls -g --depth=0 --json 2>$null | Out-String | ConvertFrom-Json
      if ($lsJson.PSObject.Properties.Name -contains 'dependencies') {
        $globals = @($lsJson.dependencies.PSObject.Properties.Name) | Where-Object { $_ -ne 'npm' }
      }
    } catch { Report-Warn "Could not parse 'npm ls -g'." }

    $insSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$globals, [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($e in @($expected) | Where-Object { -not $insSet.Contains($_) }) {
      Report-Drift "Missing npm global: $e" @("install: npm install -g $e")
    }
    foreach ($g in $globals | Where-Object { -not $expected.Contains($_) }) {
      Report-Drift "Extra npm global (not in setup): $g" @(
        "remove: npm uninstall -g $g",
        "adopt:  add 'npm install -g $g' to Ensure-NodeAndNcu in setup-windows.ps1"
      )
    }
    if (@($expected | Where-Object { -not $insSet.Contains($_) }).Count -eq 0 -and
        @($globals  | Where-Object { -not $expected.Contains($_) }).Count -eq 0) {
      Report-Ok "npm globals match setup."
    }
  }
}

# ---------- Config files ----------
if ($Config.CheckConfigFiles) {
  Write-Section "Managed config"

  # WezTerm — managed file; check the header is intact and key values still match $Config.
  $wt = $setup.WezTermConfig
  $wtPath = Join-Path $env:USERPROFILE ".wezterm.lua"
  if ($wt.Configure) {
    if (-not (Test-Path $wtPath)) {
      Report-Drift "~/.wezterm.lua missing." @("fix: .\setup-windows.ps1")
    } else {
      $lua = Get-Content $wtPath -Raw
      if ($lua -notmatch 'Managed by devbox') {
        Report-Drift "~/.wezterm.lua has no devbox header — hand-replaced." @(
          "fix: .\setup-windows.ps1 (overwrites)",
          "keep edits: port them into the WezTermConfig block in setup-windows.ps1"
        )
      } else {
        $checks = @(
          @{ Name = "font_size";    Want = "$($wt.FontSize)";     Pattern = "config.font_size\s*=\s*$($wt.FontSize)\b" },
          @{ Name = "color_scheme"; Want = $wt.ColorScheme;       Pattern = "color_scheme\s*=\s*'$([regex]::Escape($wt.ColorScheme))'" },
          @{ Name = "cursor";       Want = $wt.CursorStyle;       Pattern = "default_cursor_style\s*=\s*'$([regex]::Escape($wt.CursorStyle))'" },
          @{ Name = "audible_bell"; Want = $wt.AudibleBell;       Pattern = "audible_bell\s*=\s*'$([regex]::Escape($wt.AudibleBell))'" },
          @{ Name = "scrollback";   Want = "$($wt.ScrollbackLines)"; Pattern = "scrollback_lines\s*=\s*$($wt.ScrollbackLines)\b" },
          @{ Name = "tab_max_width"; Want = "$($wt.TabMaxWidth)";   Pattern = "tab_max_width\s*=\s*$($wt.TabMaxWidth)\b" }
        )
        if ($wt.TabTitleShowCwd) {
          $checks += @{ Name = "tab title cwd"; Want = "cwd"; Pattern = "format-tab-title" }
        }
        $bad = @($checks | Where-Object { $lua -notmatch $_.Pattern })
        if ($bad) {
          Report-Drift "~/.wezterm.lua drifted from `$Config: $(( $bad | ForEach-Object { $_.Name }) -join ', ')" @(
            "fix: .\setup-windows.ps1 (regenerates the file)"
          )
        } else { Report-Ok "~/.wezterm.lua matches setup." }
      }
    }
  }

  # PowerShell profiles — Starship init + PSReadLine/PSFzf managed block.
  $docs = [Environment]::GetFolderPath("MyDocuments")
  $profiles = @(
    @{ Name = "PS7"; Path = Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1" }
    @{ Name = "PS5"; Path = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1" }
  )
  foreach ($p in $profiles) {
    $content = if (Test-Path $p.Path) { Get-Content $p.Path -Raw } else { "" }
    if ($setup.Starship.Configure -and $content -notmatch 'starship init') {
      Report-Drift "$($p.Name) profile missing Starship init." @("fix: .\setup-windows.ps1")
    }
    $blocks = @(
      @{ Enabled = $setup.ConfigurePwshExtras; Marker = "PSReadLine predictions"; Label = "PSReadLine/PSFzf"; Func = "Ensure-PowerShellExperience" }
      @{ Enabled = $setup.ShowCwdInTabTitle;   Marker = "tab title";              Label = "tab-title";        Func = "Ensure-ShellTabTitle" }
    )
    foreach ($b in $blocks) {
      if (-not $b.Enabled) { continue }
      $pattern = "(?ms)^# --- devbox: $([regex]::Escape($b.Marker)).*?^# --- end devbox block ---"
      if ($content -notmatch $pattern) {
        Report-Drift "$($p.Name) profile missing $($b.Label) block." @("fix: .\setup-windows.ps1")
        continue
      }
      $expected = Get-ManagedBlockText -Path $Config.SetupScript -FunctionName $b.Func
      if ($expected -and $Matches[0].Trim() -ne $expected) {
        Report-Drift "$($p.Name) profile has an outdated $($b.Label) block." @(
          "fix: .\setup-windows.ps1 (rewrites the block in place)"
        )
      }
    }
    # Only the last prompt engine to initialise wins; a second one is wasted startup
    # time at best, and a broken command at worst once its binary is uninstalled.
    if ($setup.Starship.Configure -and $content -match 'oh-my-posh') {
      Report-Drift "$($p.Name) profile initialises oh-my-posh as well as Starship." @(
        "fix: remove the oh-my-posh line from $($p.Path)",
        "keep it instead: set `$Config.Starship.Configure = `$false in setup-windows.ps1"
      )
    }
  }

  # ~/.wslconfig — networkingMode + a rough RAM sanity check.
  $wslConfPath = Join-Path $env:USERPROFILE ".wslconfig"
  if (Test-Path $wslConfPath) {
    $wslText = Get-Content $wslConfPath -Raw
    $wantNet = $setup.WslConfig.networkingMode
    if ($wantNet -and $wslText -notmatch "networkingMode\s*=\s*$([regex]::Escape($wantNet))") {
      Report-Drift ".wslconfig networkingMode is not '$wantNet'." @("fix: .\setup-windows.ps1")
    } else { Report-Ok ".wslconfig networkingMode = $wantNet." }
  } else {
    Report-Drift ".wslconfig missing." @("fix: .\setup-windows.ps1")
  }

  # Dev Drive package-cache env vars.
  $dd = $setup.DevDrivePackageCaches
  if ($dd.Configure) {
    $expectVars = @{}
    if ($dd.Npm)   { $expectVars["npm_config_cache"] = (Join-Path $dd.Root "npm") }
    if ($dd.NuGet) {
      $expectVars["NUGET_PACKAGES"]           = (Join-Path $dd.Root "nuget\packages")
      $expectVars["NUGET_HTTP_CACHE_PATH"]    = (Join-Path $dd.Root "nuget\http")
      $expectVars["NUGET_PLUGINS_CACHE_PATH"] = (Join-Path $dd.Root "nuget\plugins")
    }
    foreach ($name in $expectVars.Keys) {
      $cur = [Environment]::GetEnvironmentVariable($name, "User")
      if ($cur -ne $expectVars[$name]) {
        Report-Drift "env $name = '$cur' (expected '$($expectVars[$name])')." @("fix: .\setup-windows.ps1")
      }
    }
  }

  # Claude Code's winget self-upgrade switch (~/.claude/settings.json is Claude
  # Code's own file, so setup merges this one key in rather than owning the file).
  if ($setup.InstallClaudeCode -and $setup.ClaudeCodeAutoUpdate) {
    $ccPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    $ccVal = $null
    if (Test-Path $ccPath) {
      $ccJson = $null
      try { $ccJson = Get-Content $ccPath -Raw | ConvertFrom-Json }
      catch { Report-Warn "~/.claude/settings.json is not valid JSON — cannot check auto-update." }
      # Strict mode makes a missing property a terminating error, so walk both
      # levels explicitly instead of chaining .env.CLAUDE_CODE_...
      # Filtered, not .PSObject.Properties.Name: strict mode makes member
      # enumeration over an empty property set a terminating error.
      if ($ccJson -and ($ccJson.PSObject.Properties | Where-Object { $_.Name -eq "env" })) {
        $ccProp = $ccJson.env.PSObject.Properties |
          Where-Object { $_.Name -eq "CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE" }
        if ($ccProp) { $ccVal = $ccProp.Value }
      }
    }
    if ("$ccVal" -ne "1") {
      Report-Drift "Claude Code winget auto-upgrade is off (env CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE = '$ccVal')." @(
        "fix: .\setup-windows.ps1",
        "keep it off: set ClaudeCodeAutoUpdate = `$false in setup-windows.ps1"
      )
    } else { Report-Ok "Claude Code upgrades its own winget package." }
  }

  # Git global config keys setup manages.
  if ($setup.GitConfig.Configure -and (Test-Command "git")) {
    $gitWant = @{
      "core.autocrlf"        = $setup.GitConfig.AutoCRLF
      "init.defaultBranch"   = $setup.GitConfig.DefaultBranch
      "pull.rebase"          = $setup.GitConfig.PullRebase
      "push.autoSetupRemote" = $setup.GitConfig.AutoSetupRemote
    }
    foreach ($k in $gitWant.Keys) {
      $cur = (git config --global --get $k) 2>$null
      if ($cur -ne $gitWant[$k]) {
        Report-Drift "git $k = '$cur' (expected '$($gitWant[$k])')." @("fix: git config --global $k $($gitWant[$k])")
      }
    }
  }
}

# ---------- Startup & services ----------
if ($Config.CheckStartup) {
  Write-Section "Startup & services"

  # --- devbox-managed autostart (drift if wrong) ---

  # Dev Drive re-attach task registered by bootstrap-windows.ps1.
  $devDriveTask = "DevboxMountDevDrive"
  $task = Get-ScheduledTask -TaskName $devDriveTask -ErrorAction SilentlyContinue
  if ($task) {
    if ($task.State -eq 'Disabled') {
      Report-Drift "Scheduled task '$devDriveTask' is disabled." @("fix: Enable-ScheduledTask -TaskName $devDriveTask")
    } else {
      Report-Ok "Scheduled task '$devDriveTask' present ($($task.State))."
    }
  } else {
    Report-Warn "Scheduled task '$devDriveTask' not found (expected only if the Dev Drive was created by bootstrap-windows.ps1)."
  }

  # ssh-agent — setup sets StartupType Automatic.
  $ssh = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
  if ($ssh) {
    if ($ssh.StartType -ne 'Automatic') {
      Report-Drift "ssh-agent StartupType is '$($ssh.StartType)' (expected Automatic)." @(
        "fix: Set-Service -Name ssh-agent -StartupType Automatic",
        "or rerun: .\setup-windows.ps1"
      )
    } else {
      Report-Ok "ssh-agent StartupType = Automatic (Status: $($ssh.Status))."
    }
  } else {
    Report-Warn "ssh-agent service not found (enable OpenSSH Client in Optional Features)."
  }

  # --- autostart inventory (informational — not counted as drift) ---
  Write-Host "  autostart inventory (informational — review, adopt into setup, or remove):" -ForegroundColor DarkGray

  # Non-Microsoft scheduled tasks that fire at logon or boot.
  try {
    $userTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
      $_.TaskName -ne $devDriveTask -and
      $_.TaskPath -notlike '\Microsoft\*' -and
      $_.State -ne 'Disabled' -and
      @($_.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger','MSFT_TaskBootTrigger' }).Count -gt 0
    })
    foreach ($t in $userTasks) { Report-Info "task (logon/boot): $($t.TaskPath)$($t.TaskName)" }
  } catch {}

  # Run keys (per-user + machine, incl. WOW6432Node).
  $runKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
  )
  foreach ($rk in $runKeys) {
    if (Test-Path $rk) {
      $props = Get-ItemProperty $rk
      foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -notmatch '^PS(Path|ParentPath|ChildName|Provider|Drive)$') {
          Report-Info "Run key [$(Split-Path $rk -Leaf)@$($rk.Split(':')[0])]: $($p.Name)"
        }
      }
    }
  }

  # Startup-folder shortcuts (user + all-users).
  $startupDirs = @(
    [Environment]::GetFolderPath('Startup'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')
  )
  foreach ($d in $startupDirs) {
    if ($d -and (Test-Path $d)) {
      foreach ($item in Get-ChildItem $d -File -ErrorAction SilentlyContinue) {
        Report-Info "startup folder: $($item.Name)"
      }
    }
  }

  # Auto-start services running from outside %SystemRoot% (i.e. third-party).
  try {
    $sysRoot = $env:SystemRoot
    $svcs = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
      $_.StartMode -eq 'Auto' -and $_.PathName -and ($_.PathName -notmatch [regex]::Escape($sysRoot))
    })
    foreach ($s in $svcs | Sort-Object Name) {
      Report-Info "auto service: $($s.Name) [$($s.State)]"
    }
  } catch {}
}

# ---------- summary ----------
Write-Host ""
if ($script:driftCount -eq 0) {
  Write-Host "No drift detected — machine matches setup." -ForegroundColor Green
} else {
  Write-Host "$($script:driftCount) drift item(s) found. Each lists a fix and (for extras) how to adopt it into setup." -ForegroundColor Yellow
}
