param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$PackageDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$packageSource = (Resolve-Path $PackageDirectory).Path
$installerScript = Join-Path $repoRoot ".github/installer/DiscordVideo.iss"
$expectedInstaller = Join-Path $OutputDirectory "Windows-x64-Setup_v$Version.exe"

if (-not (Test-Path (Join-Path $packageSource "DiscordVideo.exe"))) {
    throw "The packaged DiscordVideo launcher was not found"
}
if (-not (Test-Path (Join-Path $packageSource "bin/DiscordVideoApp.exe"))) {
    throw "The packaged Qt application was not found"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$isccCandidates = @()
$isccCommand = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
if ($isccCommand) {
    $isccCandidates += $isccCommand.Source
}
$isccCandidates += Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6/ISCC.exe"
$isccCandidates += Join-Path $env:ProgramFiles "Inno Setup 6/ISCC.exe"
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw "ISCC.exe was not found"
}

$env:DISCORDVIDEO_INSTALLER_VERSION = $Version
$env:DISCORDVIDEO_INSTALLER_PACKAGE_SOURCE = $packageSource
$env:DISCORDVIDEO_INSTALLER_OUTPUT = (Resolve-Path $OutputDirectory).Path
$env:DISCORDVIDEO_INSTALLER_ICON = (Resolve-Path (Join-Path $repoRoot "app/assets/DiscordVideo.ico")).Path

try {
    & $iscc $installerScript
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item Env:DISCORDVIDEO_INSTALLER_VERSION -ErrorAction SilentlyContinue
    Remove-Item Env:DISCORDVIDEO_INSTALLER_PACKAGE_SOURCE -ErrorAction SilentlyContinue
    Remove-Item Env:DISCORDVIDEO_INSTALLER_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:DISCORDVIDEO_INSTALLER_ICON -ErrorAction SilentlyContinue
}

if (-not (Test-Path $expectedInstaller)) {
    throw "The expected installer was not created: $expectedInstaller"
}

Write-Output $expectedInstaller
