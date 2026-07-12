# =========================
# PARAMETERS (edit these)
# =========================
#
# Minimal first-run bootstrap for a BLANK, Entra-joined Windows PC.
# Ensures the prerequisites that setup-windows.ps1 assumes already exist:
#   1. winget (App Installer)      — verified, not installed (comes from the Store)
#   2. Git                          — winget-installed if missing
#   3. A Dev Drive at D:            — created as a VHDX (ReFS, trusted) if absent
#   4. This repo cloned to D:\code  — so setup-windows.ps1 is on disk to run
#
# It intentionally does NOT install apps or touch WSL — that's setup-windows.ps1's job.
# Run this once on a fresh machine, then run .\setup-windows.ps1 from the cloned folder.

$Config = @{
  # Dev Drive (backed by an expandable VHDX file — needs no unallocated disk space)
  DevDrive = @{
    Create      = $true
    Letter      = "D"                      # target drive letter
    Label       = "Dev"                    # volume label
    SizeGB      = 64                        # VHDX max size (Dev Drive minimum is 50 GB)
    VhdxPath    = "C:\DevDrives\Dev.vhdx"   # backing file; re-attached at boot via a scheduled task
    FallbackNTFS = $true                    # if Dev Drive (ReFS) is unsupported, format NTFS instead
  }

  # Repo to clone once the Dev Drive exists
  Repo = @{
    Url       = "https://github.com/tsolbjor/devbox.git"
    CloneRoot = "D:\code"                   # parent dir; repo lands in <CloneRoot>\<repo name>
  }
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

# Pull the freshly-updated machine + user PATH into this session so a just-installed
# tool (e.g. git) resolves without opening a new terminal.
function Update-SessionPath {
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Ensure-Winget {
  if (Test-Command "winget") {
    Write-Host "✓ winget available" -ForegroundColor Green
    return
  }
  throw "winget is not available. Install 'App Installer' from the Microsoft Store (or run 'winget' once to trigger setup), then rerun this script."
}

function Ensure-Git {
  if (Test-Command "git") {
    Write-Host "✓ Git already installed" -ForegroundColor Green
    return
  }
  Write-Host "→ Installing Git" -ForegroundColor Cyan
  winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements
  Update-SessionPath
  if (-not (Test-Command "git")) {
    throw "Git was installed but is still not on PATH. Open a new terminal and rerun this script."
  }
}

# Create an expandable-VHDX-backed Dev Drive and assign it a drive letter.
# Uses diskpart (create/attach/partition) + Format-Volume -DevDrive (ReFS + trust flag).
# No Hyper-V module required.
function Ensure-DevDrive {
  param([Parameter(Mandatory=$true)]$Spec)

  if (-not $Spec.Create) { return }

  $letter = $Spec.Letter.TrimEnd(":")
  if (Test-Path "$letter`:\") {
    Write-Host "✓ Drive $letter`: already exists — skipping Dev Drive creation" -ForegroundColor Green
    return
  }

  if (Test-Path $Spec.VhdxPath) {
    Write-Host "→ VHDX $($Spec.VhdxPath) exists but is not attached — attaching" -ForegroundColor Cyan
    Mount-DiskImage -ImagePath $Spec.VhdxPath | Out-Null
    Register-DevDriveAutoMount -VhdxPath $Spec.VhdxPath
    return
  }

  Write-Host "→ Creating Dev Drive $letter`: ($($Spec.SizeGB) GB, VHDX at $($Spec.VhdxPath))" -ForegroundColor Cyan

  $vhdxDir = Split-Path $Spec.VhdxPath -Parent
  if (-not (Test-Path $vhdxDir)) { New-Item -ItemType Directory -Path $vhdxDir -Force | Out-Null }

  $sizeMB = [int]$Spec.SizeGB * 1024
  $diskpartScript = @"
create vdisk file="$($Spec.VhdxPath)" maximum=$sizeMB type=expandable
select vdisk file="$($Spec.VhdxPath)"
attach vdisk
convert gpt
create partition primary
assign letter=$letter
exit
"@
  $dpFile = Join-Path $env:TEMP "devbox-devdrive.txt"
  Set-Content -Path $dpFile -Value $diskpartScript -Encoding ASCII
  try {
    $out = & diskpart.exe /s $dpFile 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "diskpart failed:`n$out" }
  } finally {
    Remove-Item $dpFile -ErrorAction SilentlyContinue
  }

  Format-DevVolume -Letter $letter -Spec $Spec
  Register-DevDriveAutoMount -VhdxPath $Spec.VhdxPath
  Write-Host "✓ Dev Drive $letter`: ready" -ForegroundColor Green
}

# Format the freshly-created partition as a Dev Drive (ReFS + trust), or NTFS as fallback.
function Format-DevVolume {
  param([string]$Letter, $Spec)

  $supportsDevDrive = (Get-Command Format-Volume).Parameters.ContainsKey("DevDrive")
  if ($supportsDevDrive) {
    try {
      Format-Volume -DriveLetter $Letter -DevDrive -FileSystemLabel $Spec.Label -Confirm:$false | Out-Null
      Write-Host "✓ Formatted $Letter`: as a Dev Drive (ReFS)" -ForegroundColor Green
      return
    } catch {
      Write-Warning "Dev Drive formatting failed ($($_.Exception.Message))."
    }
  } else {
    Write-Warning "This Windows build does not support Dev Drive (requires Windows 11 22H2 build 22621.2338+)."
  }

  if ($Spec.FallbackNTFS) {
    Write-Warning "Falling back to NTFS for $Letter`:."
    Format-Volume -DriveLetter $Letter -FileSystem NTFS -NewFileSystemLabel $Spec.Label -Confirm:$false | Out-Null
    Write-Host "✓ Formatted $Letter`: as NTFS" -ForegroundColor Green
  } else {
    throw "Could not format $Letter`: as a Dev Drive and FallbackNTFS is disabled."
  }
}

# A diskpart-attached VHDX does not survive a reboot. Register a startup scheduled task
# (runs as SYSTEM) that re-attaches it so D: is present on every boot.
function Register-DevDriveAutoMount {
  param([Parameter(Mandatory=$true)][string]$VhdxPath)

  $taskName = "DevboxMountDevDrive"
  $action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"Mount-DiskImage -ImagePath '$VhdxPath'`""
  $trigger = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
  Write-Host "✓ Registered boot task '$taskName' to re-attach the Dev Drive" -ForegroundColor Green
}

function Ensure-Repo {
  param([Parameter(Mandatory=$true)]$Spec)

  if (-not (Test-Path $Spec.CloneRoot)) {
    New-Item -ItemType Directory -Path $Spec.CloneRoot -Force | Out-Null
  }

  $repoName = [System.IO.Path]::GetFileNameWithoutExtension($Spec.Url)
  $target = Join-Path $Spec.CloneRoot $repoName

  if (Test-Path (Join-Path $target ".git")) {
    Write-Host "✓ Repo already cloned at $target" -ForegroundColor Green
    return $target
  }

  Write-Host "→ Cloning $($Spec.Url) → $target" -ForegroundColor Cyan
  git clone $Spec.Url $target
  return $target
}

# ---- run ----
Assert-Admin
Ensure-Winget
Ensure-Git
Ensure-DevDrive -Spec $Config.DevDrive
$repoPath = Ensure-Repo -Spec $Config.Repo

Write-Host ""
Write-Host "Bootstrap complete." -ForegroundColor Green
Write-Host "Next step — run the full setup as Administrator:" -ForegroundColor Yellow
Write-Host "    Set-Location `"$repoPath`"" -ForegroundColor White
Write-Host "    .\setup-windows.ps1" -ForegroundColor White
