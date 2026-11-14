# Builds dist/FriendsAndFoes-<version>.zip (version read from the .toc).
# The zip contains the FriendsAndFoes folder, ready to extract into _forever_\Interface\AddOns.
# Entries use forward slashes (Compress-Archive on PowerShell 5.1 writes backslashes,
# which some extractors mishandle).
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$addon = Join-Path $root "FriendsAndFoes"
$toc = Get-Content (Join-Path $addon "FriendsAndFoes.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() }) | Select-Object -First 1
if (-not $version) { throw "No '## Version:' line in FriendsAndFoes.toc" }

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "FriendsAndFoes-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force -Confirm:$false }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem $addon -Recurse -File | Where-Object { $_.Name -notlike ".*" } | ForEach-Object {
    $rel = $_.FullName.Substring($addon.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, "FriendsAndFoes/$rel") | Out-Null
  }
} finally {
  $zip.Dispose()
}
Write-Output "Built $zipPath"
