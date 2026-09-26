# Run under Windows PowerShell 5.1 (powershell.exe), the shell a fresh machine
# has and the one the README points at. Checks every .ps1 loads the two ways it
# is actually run:
#
#   from disk   — 5.1 reads a BOM-less file as the ANSI code page, where the
#                 UTF-8 bytes of ✓ / → / — include curly quotes that PowerShell
#                 parses as string delimiters. Get-Content without -Encoding
#                 decodes the way the script loader does (BOM, else ANSI), so
#                 parsing its output fails exactly as `.\x.ps1` would. (Not
#                 `(Get-Command x.ps1).ScriptBlock`: that passes a file the real
#                 loader rejects.)
#   irm | iex   — bootstrap-windows.ps1 only: it arrives as a string, where a BOM
#                 survives as a stray U+FEFF, so it must be BOM-less pure ASCII.
#
# pwsh 7 reads UTF-8 by default and passes all of this, which is why a parse
# check on Linux never caught it.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).ProviderPath
$failed = 0

"PowerShell $($PSVersionTable.PSVersion) — ANSI code page $([Text.Encoding]::Default.WebName)"

foreach ($f in Get-ChildItem $root -Filter *.ps1) {
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput(
    (Get-Content -LiteralPath $f.FullName -Raw), [ref]$null, [ref]$errors)
  if ($errors.Count -eq 0) {
    "✓ $($f.Name) loads from disk"
  } else {
    "✗ $($f.Name) does not load from disk — line $($errors[0].Extent.StartLineNumber): $($errors[0].Message)"
    $failed++
  }
}

$bootstrap = Join-Path $root "bootstrap-windows.ps1"
$bytes = [IO.File]::ReadAllBytes($bootstrap)
$nonAscii = @($bytes | Where-Object { $_ -gt 0x7F }).Count
if ($nonAscii -gt 0) {
  "✗ bootstrap-windows.ps1 has $nonAscii non-ASCII byte(s); it must stay pure ASCII for irm | iex"
  $failed++
} else {
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput(
    [Text.Encoding]::UTF8.GetString($bytes), [ref]$null, [ref]$errors)
  if ($errors.Count -gt 0) {
    "✗ bootstrap-windows.ps1 does not parse as an irm | iex string: $($errors[0].Message)"
    $failed++
  } else {
    "✓ bootstrap-windows.ps1 is pure ASCII and parses as an irm | iex string"
  }
}

if ($failed -gt 0) { exit 1 }
