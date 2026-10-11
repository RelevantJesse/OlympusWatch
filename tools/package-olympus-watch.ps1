param(
    [string]$WowPath = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_',
    [switch]$Install
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'Forever\OlympusWatch'
$dist = Join-Path $repoRoot 'Forever\dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$version = ((Get-Content -LiteralPath (Join-Path $source 'OlympusWatch.toc') | Where-Object { $_ -match '^## Version:' }) -replace '^## Version:\s*', '').Trim()
$zip = Join-Path $dist "OlympusWatch-$version.zip"
Compress-Archive -LiteralPath $source -DestinationPath $zip -Force
Write-Output "Packaged $zip"
if ($Install) {
    if (-not (Test-Path -LiteralPath (Join-Path $WowPath 'WowB.exe'))) { throw "Forever executable not found in $WowPath" }
    $destination = Join-Path $WowPath 'Interface\AddOns\OlympusWatch'
    if (Test-Path -LiteralPath $destination) {
        $backup = Join-Path $repoRoot ('Forever\backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '\OlympusWatch')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup -Recurse
        Write-Output "Backed up $destination to $backup"
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Get-ChildItem -LiteralPath $source -File | ForEach-Object {
        # Retain the public snapshot supplied by the companion during upgrades.
        if ($_.Name -ne 'ServerSync.lua' -or -not (Test-Path -LiteralPath (Join-Path $destination $_.Name))) {
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        }
    }
    Write-Output "Installed $destination"
}
