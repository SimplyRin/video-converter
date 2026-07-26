param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$BuildNumber,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$packageRoot = Join-Path $env:RUNNER_TEMP "package/DiscordVideo"
$ffmpegRoot = Join-Path $packageRoot "tools/ffmpeg"
$ffmpegArchive = Join-Path $env:RUNNER_TEMP "ffmpeg-win64-gpl.zip"
$ffmpegExtract = Join-Path $env:RUNNER_TEMP "ffmpeg-win64-gpl"
$ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.1-latest-win64-gpl-8.1.zip"
$applicationCandidates = @(
    (Join-Path $repoRoot "build/windows/Release/DiscordVideo.exe"),
    (Join-Path $repoRoot "build/windows/DiscordVideo.exe")
)
$application = $applicationCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $application) {
    throw "DiscordVideo.exe was not found in the Windows build directory"
}

New-Item -ItemType Directory -Force -Path $packageRoot, $ffmpegRoot, $OutputDirectory | Out-Null
Copy-Item $application $packageRoot

& windeployqt `
    --release `
    --compiler-runtime `
    --no-translations `
    --qmldir (Join-Path $repoRoot "app/qml") `
    (Join-Path $packageRoot "DiscordVideo.exe")
if ($LASTEXITCODE -ne 0) {
    throw "windeployqt failed with exit code $LASTEXITCODE"
}

curl.exe --fail --location --retry 5 --output $ffmpegArchive $ffmpegUrl
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg download failed with exit code $LASTEXITCODE"
}
Expand-Archive -Path $ffmpegArchive -DestinationPath $ffmpegExtract -Force

$ffmpeg = Get-ChildItem $ffmpegExtract -Recurse -File -Filter "ffmpeg.exe" | Select-Object -First 1
$ffprobe = Get-ChildItem $ffmpegExtract -Recurse -File -Filter "ffprobe.exe" | Select-Object -First 1
if (-not $ffmpeg -or -not $ffprobe) {
    throw "The BtbN archive did not contain ffmpeg.exe and ffprobe.exe"
}

Copy-Item $ffmpeg.FullName (Join-Path $ffmpegRoot "ffmpeg.exe")
Copy-Item $ffprobe.FullName (Join-Path $ffmpegRoot "ffprobe.exe")
Copy-Item (Join-Path $repoRoot "LICENSE.md") $packageRoot
Copy-Item (Join-Path $repoRoot "THIRD_PARTY_NOTICES.md") $packageRoot

@(
    "Source: $ffmpegUrl"
    "Variant: BtbN win64 GPL static build"
    ""
    (& $ffmpeg.FullName -version | Select-Object -First 12)
) | Set-Content -Encoding UTF8 (Join-Path $ffmpegRoot "BUILD-INFO.txt")

$x264Encoder = & (Join-Path $ffmpegRoot "ffmpeg.exe") -hide_banner -encoders 2>&1 |
    Select-String "libx264"
if ($LASTEXITCODE -ne 0 -or -not $x264Encoder) {
    throw "Bundled FFmpeg could not be executed or does not contain libx264"
}

$assetPath = Join-Path $OutputDirectory "Windows-x64_v$Version+$BuildNumber.zip"
Compress-Archive -Path $packageRoot -DestinationPath $assetPath -CompressionLevel Optimal
Write-Output $assetPath
