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
#
# -Triage is the one mode that writes: it walks the "Extra" findings in an
# interactive picker and folds what you tick into $Config.Ignore below, in this
# file. Nothing else on the machine is touched, and the change lands in git where
# you can read it before committing.

param(
  # Interactively choose which "Extra" findings to silence from now on.
  [switch]$Triage
)

$Config = @{
  SetupScript  = Join-Path $PSScriptRoot "setup-windows.ps1"
  UpdateScript = Join-Path $PSScriptRoot "update-windows.ps1"

  CheckApps        = $true   # winget-managed apps: installed-not-in-setup + missing
  CheckNativeApps  = $true   # apps installed outside winget by their own installer
  CheckVSCodeExts  = $true   # code --list-extensions vs $Config.VSCodeExtensions
  CheckNpmGlobals  = $true   # npm -g globals vs the ones setup installs
  CheckConfigFiles = $true   # WezTerm, PowerShell profiles, .wslconfig, cache env vars, git
  CheckStartup     = $true   # devbox-managed startup (Dev Drive task, ssh-agent) + autostart inventory

  # Things installed on purpose that are not part of the dev environment: personal
  # software, Office, browsers, runtime redistributables. Listing them here stops
  # them being reported as "Extra" without pretending setup installs them — the
  # third answer the remove/adopt hint has no room for.
  #
  # Populate interactively:  .\audit-windows.ps1 -Triage
  Ignore = @{
    Apps       = @()
    Extensions = @()
    NpmGlobals = @()
    # Regex over winget ids, for families that would otherwise need a dozen
    # literal entries each. These ship as dependencies of other packages and are
    # never something you would "adopt into setup".
    Patterns   = @(
      '^Microsoft\.VCRedist\.',
      '^Microsoft\.VCLibs',
      '^Microsoft\.UI\.Xaml\.',
      '^Microsoft\.WindowsAppRuntime',
      '^Microsoft\.DotNet\.(Desktop|ASPNET)?Runtime',
      '^Microsoft\.DotNet\.Native\.',
      '^Microsoft\.AppInstaller$',
      '^Microsoft\.WindowsApp$'
    )
  }
}

# =========================
# IMPLEMENTATION
# =========================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:driftCount   = 0
$script:ignoredCount = 0
# The "Extra" findings of each kind, kept for -Triage to offer up afterwards.
$script:extraApps = @()
$script:extraExts = @()
$script:extraNpm  = @()
# -Triage does its own rendering, so the ordinary report is collected silently.
$script:quiet = $Triage.IsPresent

function Write-Section { param([string]$Title) if (-not $script:quiet) { Write-Host "`n=== $Title ===" -ForegroundColor White } }
function Report-Ok    { param([string]$Msg) if (-not $script:quiet) { Write-Host "✓ $Msg" -ForegroundColor Green } }
function Report-Warn  { param([string]$Msg) if (-not $script:quiet) { Write-Host "⚠ $Msg" -ForegroundColor Yellow } }
# Inventory line — visibility only, never counted as drift.
function Report-Info  { param([string]$Msg) if (-not $script:quiet) { Write-Host "· $Msg" -ForegroundColor DarkGray } }
function Report-Drift {
  param([string]$Msg, [string[]]$Fix)
  $script:driftCount++
  if ($script:quiet) { return }
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

# --- ignore list ---------------------------------------------------------------

# Is this name silenced, either by an exact entry or by one of the regex patterns?
function Test-Ignored {
  param(
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name,
    [string[]]$Exact,
    [string[]]$Patterns
  )
  foreach ($e in @($Exact)) { if ($e -and $e -eq $Name) { return $true } }
  foreach ($p in @($Patterns)) { if ($p -and $Name -match $p) { return $true } }
  return $false
}

# Console checkbox picker. Returns the ticked items, or an empty array if the
# user escapes. Deliberately dependency-free: Out-GridView is absent on PS7
# without extra modules, and this has to work in whichever host the audit is run.
function Select-FromList {
  param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string[]]$Items
  )
  if ($Items.Count -eq 0) { return @() }

  $checked = New-Object 'System.Collections.Generic.HashSet[int]'
  $cursor  = 0
  # WindowHeight throws when output is redirected; fall back to something sane.
  $height = 24
  try { $height = [Console]::WindowHeight } catch { }
  $page = [Math]::Max(5, $height - 8)

  while ($true) {
    $first = [Math]::Min([Math]::Max(0, $cursor - [int]($page / 2)), [Math]::Max(0, $Items.Count - $page))
    $last  = [Math]::Min($Items.Count - 1, $first + $page - 1)

    Clear-Host
    Write-Host $Title -ForegroundColor White
    Write-Host "  ↑/↓ move   Space toggle   A all   N none   Enter confirm   Esc skip" -ForegroundColor DarkGray
    Write-Host ("  {0} of {1} ticked" -f $checked.Count, $Items.Count) -ForegroundColor DarkGray
    Write-Host ""
    for ($i = $first; $i -le $last; $i++) {
      $mark = if ($checked.Contains($i)) { "[x]" } else { "[ ]" }
      if ($i -eq $cursor) { Write-Host "> $mark $($Items[$i])" -ForegroundColor Cyan }
      else                { Write-Host "  $mark $($Items[$i])" -ForegroundColor Gray }
    }
    if ($last -lt $Items.Count - 1) {
      Write-Host ("  … {0} more" -f ($Items.Count - 1 - $last)) -ForegroundColor DarkGray
    }

    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      "UpArrow"   { if ($cursor -gt 0) { $cursor-- } }
      "DownArrow" { if ($cursor -lt $Items.Count - 1) { $cursor++ } }
      "PageUp"    { $cursor = [Math]::Max(0, $cursor - $page) }
      "PageDown"  { $cursor = [Math]::Min($Items.Count - 1, $cursor + $page) }
      "Home"      { $cursor = 0 }
      "End"       { $cursor = $Items.Count - 1 }
      "Spacebar"  {
        if ($checked.Contains($cursor)) { [void]$checked.Remove($cursor) } else { [void]$checked.Add($cursor) }
      }
      "Enter"  { Clear-Host; return @(@($checked) | Sort-Object | ForEach-Object { $Items[$_] }) }
      "Escape" { Clear-Host; return @() }
      default  {
        if     ("$($key.KeyChar)" -eq "a") { 0..($Items.Count - 1) | ForEach-Object { [void]$checked.Add($_) } }
        elseif ("$($key.KeyChar)" -eq "n") { $checked.Clear() }
      }
    }
  }
}

# Render the Ignore hashtable back as a PowerShell literal. Single-quoted
# throughout: Patterns are regexes, and a `$anchor` inside a double-quoted string
# would be swallowed as variable interpolation.
function Format-IgnoreLiteral {
  param([Parameter(Mandatory=$true)][hashtable]$Ignore)
  $nl = "`r`n"
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("@{$nl")
  foreach ($k in @("Apps", "Extensions", "NpmGlobals", "Patterns")) {
    $vals = @(@($Ignore[$k]) | Where-Object { $_ } | Sort-Object -Unique)
    if ($vals.Count -eq 0) {
      [void]$sb.Append(("    {0,-10} = @(){1}" -f $k, $nl))
      continue
    }
    [void]$sb.Append(("    {0,-10} = @({1}" -f $k, $nl))
    for ($i = 0; $i -lt $vals.Count; $i++) {
      $comma = if ($i -lt $vals.Count - 1) { "," } else { "" }
      [void]$sb.Append(("      '{0}'{1}{2}" -f ($vals[$i] -replace "'", "''"), $comma, $nl))
    }
    [void]$sb.Append("    )$nl")
  }
  [void]$sb.Append("  }")
  return $sb.ToString()
}

# Replace the Ignore block in this script, located by AST offset rather than by
# regex so a value containing braces or quotes cannot derail the splice.
function Save-IgnoreList {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][hashtable]$Ignore
  )
  $raw = Get-Content $Path -Raw
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($raw, [ref]$null, [ref]$null)
  $assign = $ast.Find({
    param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Config'
  }, $false)
  if (-not $assign) { throw "Could not locate `$Config in $Path" }
  $hash = $assign.Right.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $false)
  if (-not $hash) { throw "Could not locate the `$Config hashtable in $Path" }
  $pair = $hash.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq "Ignore" } | Select-Object -First 1
  if (-not $pair) { throw "Could not locate the Ignore block in $Path" }

  $ext = $pair.Item2.Extent
  $updated = $raw.Substring(0, $ext.StartOffset) + (Format-IgnoreLiteral -Ignore $Ignore) + $raw.Substring($ext.EndOffset)
  # No BOM: these scripts are stored without one, and Set-Content -Encoding UTF8
  # under Windows PowerShell 5.1 would add one.
  [System.IO.File]::WriteAllText($Path, $updated, (New-Object System.Text.UTF8Encoding($false)))
}

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
    # Installed through a variable (Install-WingetPackage -Id $x), so the literal
    # scrape above cannot see them.
    foreach ($f in @($setup.Fonts) + @($setup.CloudCLIs) + @($setup.CliTools)) { if ($f) { [void]$expected.Add($f) } }

    $tmp = Join-Path $env:TEMP "devbox-winget-export.json"
    winget export -o $tmp --accept-source-agreements --disable-interactivity 2>$null | Out-Null
    $installed = @()
    if (Test-Path $tmp) {
      $json = Get-Content $tmp -Raw | ConvertFrom-Json
      $installed = @($json.Sources | ForEach-Object { $_.Packages.PackageIdentifier }) | Where-Object { $_ }
      Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    $installedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$installed, [System.StringComparer]::OrdinalIgnoreCase)

    $missing  = @($expected) | Where-Object { -not $installedSet.Contains($_) }
    $extraAll = @($installed | Sort-Object -Unique) | Where-Object { -not $expected.Contains($_) }
    $extra    = @($extraAll | Where-Object {
      -not (Test-Ignored -Name $_ -Exact $Config.Ignore.Apps -Patterns $Config.Ignore.Patterns)
    })
    $script:ignoredCount += ($extraAll.Count - $extra.Count)
    $script:extraApps = $extra

    foreach ($id in $missing) {
      Report-Drift "Missing (setup installs it, not present): $id" @(
        "install: winget install --id $id -e",
        "or rerun: .\setup-windows.ps1"
      )
    }
    foreach ($id in $extra) {
      Report-Drift "Extra (installed, not in setup): $id" @(
        "remove:  winget uninstall --id $id",
        "adopt:   add `"$id`" to a `$Config array (Fonts/CloudCLIs/CliTools) or an Install-WingetPackage -Id line in setup-windows.ps1",
        "ignore:  .\audit-windows.ps1 -Triage   (not a dev tool — silence it)"
      )
    }
    if (-not $missing -and -not $extra) { Report-Ok "winget apps match setup ($($expected.Count) expected)." }
  }
}

# ---------- Native (non-winget) installs ----------
# Apps that come from their own installer because they self-update better than a
# `winget upgrade` on a maintenance run can. They are invisible to the winget
# inventory above, so they need their own presence check — the Windows
# counterpart of the expected-command list audit-ubuntu.sh parses out of setup.
if ($Config.CheckNativeApps) {
  Write-Section "native installs"
  if ($setup.InstallClaudeCode) {
    $claudeCmd = Get-Command "claude" -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
      Report-Drift "Missing (setup installs it, not present): Claude Code" @(
        "install: irm https://claude.ai/install.ps1 | iex",
        "or rerun: .\setup-windows.ps1"
      )
    } else {
      # A claude.exe outside ~/.local/bin is a winget or npm copy winning the PATH
      # race. Only the native install updates itself, so the stale one has to go —
      # a leftover winget package also shows up as "Extra" in the section above.
      $claudeNative = Join-Path $env:USERPROFILE ".local\bin"
      if ($claudeCmd.Source -notlike (Join-Path $claudeNative "*")) {
        Report-Drift "Claude Code on PATH is not the native install: $($claudeCmd.Source)" @(
          "fix:       .\setup-windows.ps1   (removes the winget copy, installs the native one)",
          "find them: where.exe claude"
        )
      } else {
        Report-Ok "Claude Code is the native install — it self-updates ($($claudeCmd.Source))."
      }
    }
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

    $missingExt  = @($expected  | Where-Object { -not $insSet.Contains($_) })
    $extraExtAll = @($installed | Where-Object { -not $expSet.Contains($_) })
    $extraExt    = @($extraExtAll | Where-Object { -not (Test-Ignored -Name $_ -Exact $Config.Ignore.Extensions) })
    $script:ignoredCount += ($extraExtAll.Count - $extraExt.Count)
    $script:extraExts = $extraExt
    foreach ($e in $missingExt) {
      Report-Drift "Missing extension: $e" @("install: code --install-extension $e")
    }
    foreach ($i in $extraExt) {
      Report-Drift "Extra extension (not in setup): $i" @(
        "remove: code --uninstall-extension $i",
        "adopt:  add `"$i`" to `$Config.VSCodeExtensions in setup-windows.ps1",
        "ignore: .\audit-windows.ps1 -Triage"
      )
    }
    if ($missingExt.Count -eq 0 -and $extraExt.Count -eq 0) {
      Report-Ok "VS Code extensions match setup."
    }
  }
}

# ---------- Node (fnm) ----------
# Setup provides Node through fnm, with npm globals in one prefix shared by every
# version. Any other node.exe — the MSI, nvm-windows — is shadowed by fnm in a
# profile-loaded shell but not elsewhere, and it rides the machine PATH into WSL.
if ($Config.CheckNpmGlobals -and $setup.InstallNode) {
  Write-Section "Node (fnm)"
  if (-not (Test-Command "fnm")) {
    Report-Drift "fnm not installed — setup provides Node through it" @("fix: .\setup-windows.ps1")
  } else {
    # Audit the fnm default whatever shell this runs in (and the npm globals
    # section below reads the same npm).
    fnm env --shell powershell | Out-String | Invoke-Expression
    $clean = $true
    $default = @(fnm list) | ForEach-Object { if ($_ -match '(v\d+\.\d+\.\d+).*\bdefault\b') { $Matches[1] } } | Select-Object -First 1
    if ($default -like "v$($setup.NodeMajorVersion).*") {
      Report-Ok "node $($setup.NodeMajorVersion).x is the fnm default ($default)."
    } else {
      $clean = $false
      Report-Drift "node (fnm default): pinned $($setup.NodeMajorVersion).x, default $(if ($default) { $default } else { 'unset' })" @(
        "fix:  fnm install $($setup.NodeMajorVersion); fnm default $($setup.NodeMajorVersion)",
        "keep: change NodeMajorVersion in setup-windows.ps1"
      )
    }

    $prefix = if ($setup.NpmGlobalPrefix) { $setup.NpmGlobalPrefix } else { Join-Path $env:APPDATA "npm" }
    $npmrc = Join-Path $env:USERPROFILE ".npmrc"
    if (-not ((Test-Path $npmrc) -and (@(Get-Content $npmrc) -contains "prefix=$prefix"))) {
      $clean = $false
      Report-Drift "npm global prefix is not $prefix (globals would be per Node version)" @("fix: .\setup-windows.ps1")
    }

    if (Test-Path (Join-Path $env:ProgramFiles "nodejs\node.exe")) {
      $clean = $false
      Report-Drift "Node.js MSI installed alongside fnm ($env:ProgramFiles\nodejs)" @(
        "fix: .\setup-windows.ps1   (offers to uninstall it; MigrateLegacyNode = 'yes' skips the prompt)",
        "or:  winget uninstall --id OpenJS.NodeJS.LTS   (or OpenJS.NodeJS)"
      )
    }
    if ($env:NVM_HOME) {
      $clean = $false
      Report-Drift "nvm-windows installed alongside fnm ($env:NVM_HOME)" @(
        "fix: .\setup-windows.ps1   (offers to move its globals under fnm and uninstall it)",
        "or:  winget uninstall --id CoreyButler.NVMforWindows"
      )
    }
    $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
    if ($nodeCmd -and $nodeCmd.Source -notmatch 'fnm_multishells') {
      $clean = $false
      Report-Drift "node on PATH is not fnm's: $($nodeCmd.Source)" @("find them: where.exe node")
    }
    if ($clean) { Report-Ok "fnm is the only Node provider; npm globals in $prefix." }
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
    $missingNpm  = @($expected | Where-Object { -not $insSet.Contains($_) })
    $extraNpmAll = @($globals  | Where-Object { -not $expected.Contains($_) })
    $extraNpm    = @($extraNpmAll | Where-Object { -not (Test-Ignored -Name $_ -Exact $Config.Ignore.NpmGlobals) })
    $script:ignoredCount += ($extraNpmAll.Count - $extraNpm.Count)
    $script:extraNpm = $extraNpm

    foreach ($e in $missingNpm) {
      Report-Drift "Missing npm global: $e" @("install: npm install -g $e")
    }
    foreach ($g in $extraNpm) {
      Report-Drift "Extra npm global (not in setup): $g" @(
        "remove: npm uninstall -g $g",
        "adopt:  add 'npm install -g $g' to Ensure-Node in setup-windows.ps1",
        "ignore: .\audit-windows.ps1 -Triage"
      )
    }
    if ($missingNpm.Count -eq 0 -and $extraNpm.Count -eq 0) {
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
        # Not $Config-derived, so the loop above would never notice these going
        # stale on a machine whose .wezterm.lua predates them. Markers only —
        # enough to tell "regenerated since" from "written by an older setup".
        if ($setup.InstallPowerShell7) {
          $checks += @{ Name = "default_prog=pwsh"; Want = "pwsh"; Pattern = "config\.default_prog\s*=\s*\{\s*'pwsh\.exe'" }
        }
        $checks += @{ Name = "directional splits"; Want = "SplitPane"; Pattern = "SplitPane\s*\{\s*direction\s*=\s*'Left'" }

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
      @{ Enabled = $setup.InstallNode;         Marker = "fnm";                    Label = "fnm";              Func = "Ensure-Node" }
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

  # Git global config keys setup manages.
  if ($setup.GitConfig.Configure -and (Test-Command "git")) {
    $gitWant = @{
      "core.autocrlf"        = $setup.GitConfig.AutoCRLF
      "init.defaultBranch"   = $setup.GitConfig.DefaultBranch
      "pull.rebase"          = $setup.GitConfig.PullRebase
      "push.autoSetupRemote" = $setup.GitConfig.AutoSetupRemote
    }
    if ($setup.GitConfig.UseDelta) {
      $gitWant["core.pager"]             = "delta"
      $gitWant["interactive.diffFilter"] = "delta --color-only"
      $gitWant["delta.navigate"]         = "true"
    }
    foreach ($k in $gitWant.Keys) {
      $cur = (git config --global --get $k) 2>$null
      if ($cur -ne $gitWant[$k]) {
        # Quoted: values like "delta --color-only" contain spaces, and an unquoted
        # hint would be pasted as two arguments and set the wrong thing.
        Report-Drift "git $k = '$cur' (expected '$($gitWant[$k])')." @("fix: git config --global $k `"$($gitWant[$k])`"")
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

# ---------- triage ----------
# The one writing mode. Walks each category of "Extra" finding through a checkbox
# picker and folds the ticked entries into $Config.Ignore in this file. Nothing
# else is touched: the machine is left exactly as found, and the edit lands in
# git where it can be read before committing.
if ($Triage) {
  $ignore = @{
    Apps       = @($Config.Ignore.Apps)
    Extensions = @($Config.Ignore.Extensions)
    NpmGlobals = @($Config.Ignore.NpmGlobals)
    Patterns   = @($Config.Ignore.Patterns)
  }

  $rounds = @(
    @{ Key = "Apps";       Items = $script:extraApps; Label = "winget apps" },
    @{ Key = "Extensions"; Items = $script:extraExts; Label = "VS Code extensions" },
    @{ Key = "NpmGlobals"; Items = $script:extraNpm;  Label = "npm globals" }
  )

  $added = 0
  foreach ($r in $rounds) {
    $items = @($r.Items)
    if ($items.Count -eq 0) { continue }
    $title = "Extra $($r.Label) — tick the ones that are NOT drift (personal software, not dev tooling)"
    $picked = @(Select-FromList -Title $title -Items $items)
    if ($picked.Count -gt 0) {
      $ignore[$r.Key] = @(@($ignore[$r.Key]) + $picked | Where-Object { $_ } | Sort-Object -Unique)
      $added += $picked.Count
    }
  }

  if ($added -eq 0) {
    Write-Host "Nothing ticked — $(Split-Path $PSCommandPath -Leaf) left unchanged." -ForegroundColor Green
    return
  }

  Save-IgnoreList -Path $PSCommandPath -Ignore $ignore
  Write-Host "Added $added entr$(if ($added -eq 1) { 'y' } else { 'ies' }) to `$Config.Ignore in $(Split-Path $PSCommandPath -Leaf)." -ForegroundColor Green
  Write-Host "Review with: git diff $(Split-Path $PSCommandPath -Leaf)" -ForegroundColor DarkGray
  return
}

# ---------- summary ----------
Write-Host ""
if ($script:driftCount -eq 0) {
  Write-Host "No drift detected — machine matches setup." -ForegroundColor Green
} else {
  Write-Host "$($script:driftCount) drift item(s) found. Each lists a fix and (for extras) how to adopt it into setup." -ForegroundColor Yellow
}
if ($script:ignoredCount -gt 0) {
  Write-Host "$($script:ignoredCount) extra(s) silenced by `$Config.Ignore. Revisit with: .\audit-windows.ps1 -Triage" -ForegroundColor DarkGray
}
