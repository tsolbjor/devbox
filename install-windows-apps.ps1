# =========================
# PARAMETERS (edit these)
# =========================

$Config = @{
  # .NET SDK version
  DotNetVersion = "8.0"
  
  # Node.js version
  NodeVersion = "20"
  
  # Optional installs (set to $false to skip)
  InstallDotNet           = $true
  InstallNodeJS           = $true
  InstallAzureCLI         = $true
  InstallAzureDeveloperCLI = $true
  InstallAzCopy           = $true
  InstallOhMyPosh         = $true
  InstallPowerToys        = $true
  InstallDevTunnel        = $true
  Install7Zip             = $true
  InstallJetBrainsToolbox = $true
  InstallPostman          = $true
  InstallFigma            = $true
  InstallWinSCP           = $true
  
  # npm packages (installed after Node.js)
  InstallTypeScript       = $true
  InstallAzureFunctions   = $true
  InstallCopilotCLI       = $true
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

function Install-NpmGlobal {
  param(
    [Parameter(Mandatory=$true)][string]$Package
  )
  
  $installed = npm list -g $Package 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ npm package already installed globally: $Package" -ForegroundColor Green
    return
  }
  
  Write-Host "→ Installing npm package globally: $Package" -ForegroundColor Cyan
  npm install -g $Package
}

function Install-DotNetTool {
  param(
    [Parameter(Mandatory=$true)][string]$ToolName
  )
  
  $tools = dotnet tool list -g 2>$null | Out-String
  if ($tools -match [regex]::Escape($ToolName)) {
    Write-Host "✓ dotnet tool already installed: $ToolName" -ForegroundColor Green
    return
  }
  
  Write-Host "→ Installing dotnet tool: $ToolName" -ForegroundColor Cyan
  dotnet tool install -g $ToolName
}

# =========================
# RUN
# =========================

Ensure-Winget

# Install .NET SDK
if ($Config.InstallDotNet) {
  Write-Host "`n=== Installing .NET SDK ===" -ForegroundColor Yellow
  if (Test-Command "dotnet") {
    Write-Host "✓ .NET SDK already installed" -ForegroundColor Green
  } else {
    Install-WingetPackage -Id "Microsoft.DotNet.SDK.$($Config.DotNetVersion)"
  }
}

# Install Node.js
if ($Config.InstallNodeJS) {
  Write-Host "`n=== Installing Node.js ===" -ForegroundColor Yellow
  if (Test-Command "node") {
    Write-Host "✓ Node.js already installed" -ForegroundColor Green
  } else {
    Install-WingetPackage -Id "OpenJS.NodeJS.LTS"
  }
}

# Install TypeScript globally via npm
if ($Config.InstallTypeScript -and $Config.InstallNodeJS) {
  Write-Host "`n=== Installing TypeScript ===" -ForegroundColor Yellow
  if (Test-Command "node") {
    Install-NpmGlobal -Package "typescript"
  } else {
    Write-Warning "Node.js not available, skipping TypeScript"
  }
}

# Install Azure Functions Core Tools via npm
if ($Config.InstallAzureFunctions -and $Config.InstallNodeJS) {
  Write-Host "`n=== Installing Azure Functions Core Tools ===" -ForegroundColor Yellow
  if (Test-Command "node") {
    Install-NpmGlobal -Package "azure-functions-core-tools@4"
  } else {
    Write-Warning "Node.js not available, skipping Azure Functions Core Tools"
  }
}

# Install Azure CLI
if ($Config.InstallAzureCLI) {
  Write-Host "`n=== Installing Azure CLI ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "Microsoft.AzureCLI"
}

# Install Azure Developer CLI
if ($Config.InstallAzureDeveloperCLI) {
  Write-Host "`n=== Installing Azure Developer CLI ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "Microsoft.Azd"
}

# Install AzCopy
if ($Config.InstallAzCopy) {
  Write-Host "`n=== Installing AzCopy ===" -ForegroundColor Yellow
  if (Test-Command "azcopy") {
    Write-Host "✓ AzCopy already installed" -ForegroundColor Green
  } else {
    Install-WingetPackage -Id "Microsoft.AzCopy.10"
  }
}

# Install oh-my-posh
if ($Config.InstallOhMyPosh) {
  Write-Host "`n=== Installing oh-my-posh ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "JanDeDobbeleer.OhMyPosh"
}

# Install PowerToys
if ($Config.InstallPowerToys) {
  Write-Host "`n=== Installing PowerToys ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "Microsoft.PowerToys"
}

# Install devtunnel via dotnet tool
if ($Config.InstallDevTunnel) {
  Write-Host "`n=== Installing devtunnel ===" -ForegroundColor Yellow
  if (Test-Command "dotnet") {
    Install-DotNetTool -ToolName "Microsoft.devtunnel"
  } else {
    Write-Warning ".NET SDK not available, skipping devtunnel"
  }
}

# Install 7zip
if ($Config.Install7Zip) {
  Write-Host "`n=== Installing 7zip ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "7zip.7zip"
}

# Install JetBrains Toolbox
if ($Config.InstallJetBrainsToolbox) {
  Write-Host "`n=== Installing JetBrains Toolbox ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "JetBrains.Toolbox"
}

# Install Postman
if ($Config.InstallPostman) {
  Write-Host "`n=== Installing Postman ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "Postman.Postman"
}

# Install Figma
if ($Config.InstallFigma) {
  Write-Host "`n=== Installing Figma ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "Figma.Figma"
}

# Install WinSCP
if ($Config.InstallWinSCP) {
  Write-Host "`n=== Installing WinSCP ===" -ForegroundColor Yellow
  Install-WingetPackage -Id "WinSCP.WinSCP"
}

# Install GitHub Copilot CLI
if ($Config.InstallCopilotCLI -and $Config.InstallNodeJS) {
  Write-Host "`n=== Installing GitHub Copilot CLI ===" -ForegroundColor Yellow
  if (Test-Command "node") {
    Install-NpmGlobal -Package "@githubnext/github-copilot-cli"
    Write-Host "Run: github-copilot-cli auth to authenticate" -ForegroundColor Cyan
  } else {
    Write-Warning "Node.js not available, skipping GitHub Copilot CLI"
  }
}

Write-Host "`n=== Installation Complete ===" -ForegroundColor Green
Write-Host "`nSummary of installed tools:" -ForegroundColor Yellow

# Display summary
$summary = @(
  @{ Name = ".NET SDK"; Command = "dotnet" }
  @{ Name = "Node.js"; Command = "node" }
  @{ Name = "npm"; Command = "npm" }
  @{ Name = "TypeScript"; Command = "tsc" }
  @{ Name = "Azure Functions"; Command = "func" }
  @{ Name = "Azure CLI"; Command = "az" }
  @{ Name = "Azure Developer CLI"; Command = "azd" }
  @{ Name = "AzCopy"; Command = "azcopy" }
  @{ Name = "oh-my-posh"; Command = "oh-my-posh" }
  @{ Name = "PowerToys"; Command = "powertoys" }
  @{ Name = "devtunnel"; Command = "devtunnel" }
  @{ Name = "7zip"; Command = "7z" }
  @{ Name = "JetBrains Toolbox"; Command = "jetbrains-toolbox" }
  @{ Name = "Postman"; Command = "postman" }
  @{ Name = "Figma"; Command = "figma" }
  @{ Name = "WinSCP"; Command = "winscp" }
  @{ Name = "GitHub Copilot CLI"; Command = "github-copilot-cli" }
)

foreach ($tool in $summary) {
  $installed = if (Test-Command $tool.Command) { "✓ installed" } else { "- skipped" }
  Write-Host "  $($tool.Name): $installed"
}

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  - Restart your terminal to refresh PATH"
Write-Host "  - Configure oh-my-posh: Add 'oh-my-posh init pwsh | Invoke-Expression' to your PowerShell profile"
Write-Host "  - For JetBrains Toolbox, launch it from Start Menu to complete setup"
Write-Host "  - For devtunnel, run: devtunnel user login"
