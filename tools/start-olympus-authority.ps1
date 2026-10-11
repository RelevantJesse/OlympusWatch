param(
    [string]$AuthorityHome = (Join-Path $env:LOCALAPPDATA 'OlympusWatchAuthority'),
    [string]$ClientProfile = '',
    [switch]$ServerOnly
)
$ErrorActionPreference = 'Stop'
$taskPython = (Get-Command python -ErrorAction Stop).Source
$taskScript = Join-Path $PSScriptRoot 'olympus-authority.py'
$taskHome = [System.IO.Path]::GetFullPath($AuthorityHome)
$taskProfilePath = if ($ClientProfile) { [System.IO.Path]::GetFullPath($ClientProfile) } else { Join-Path $taskHome 'owner-client.json' }
if (-not $ClientProfile -and -not (Test-Path -LiteralPath $taskProfilePath -PathType Leaf)) {
    $taskProfilePath = Join-Path $PSScriptRoot '.private/owner-client.json'
}
if (-not (Test-Path -LiteralPath $taskProfilePath -PathType Leaf)) {
    throw "Companion credential profile missing: $taskProfilePath. Oracle is deployed; restore owner-client.json or supply -ClientProfile. Do not initialize a new authority."
}
$taskProfileData = Get-Content -LiteralPath $taskProfilePath -Raw | ConvertFrom-Json
if (-not $taskProfileData.token) { throw 'Companion profile has no credential.' }
if ($taskProfileData.url -notlike 'https://*') { throw 'Companion profile must point to the deployed HTTPS authority.' }
$taskRemotePublic = Invoke-RestMethod -Uri ($taskProfileData.url.TrimEnd('/') + '/public') -TimeoutSec 15
if (-not $taskRemotePublic.modulus) { throw 'Remote authority unavailable' }
Write-Output 'Verified Oracle HTTPS connection.'
if (-not $ServerOnly) {
    Start-Process -FilePath $taskPython -WindowStyle Hidden -ArgumentList @("`"$taskScript`"", '--home', "`"$taskHome`"", 'gui', '--profile', "`"$taskProfilePath`"") | Out-Null
    Write-Output 'Opened OlympusWatch companion.'
}
