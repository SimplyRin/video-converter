param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$BuildNumber,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$packageRoot = Join-Path $env:RUNNER_TEMP "package/DiscordVideo"
$binRoot = Join-Path $packageRoot "bin"
$ffmpegRoot = Join-Path $binRoot "tools/ffmpeg"
$ffmpegArchive = Join-Path $env:RUNNER_TEMP "ffmpeg-win64-gpl.zip"
$ffmpegExtract = Join-Path $env:RUNNER_TEMP "ffmpeg-win64-gpl"
$ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.1-latest-win64-gpl-8.1.zip"
$launcherCandidates = @(
    (Join-Path $repoRoot "build/windows/Release/DiscordVideo.exe"),
    (Join-Path $repoRoot "build/windows/DiscordVideo.exe")
)
$applicationCandidates = @(
    (Join-Path $repoRoot "build/windows/Release/DiscordVideoApp.exe"),
    (Join-Path $repoRoot "build/windows/DiscordVideoApp.exe")
)
$launcher = $launcherCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$application = $applicationCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $launcher) {
    throw "DiscordVideo launcher was not found in the Windows build directory"
}
if (-not $application) {
    throw "DiscordVideoApp.exe was not found in the Windows build directory"
}

New-Item -ItemType Directory -Force -Path $packageRoot, $binRoot, $ffmpegRoot, $OutputDirectory | Out-Null
Copy-Item $launcher $packageRoot
Copy-Item $application $binRoot

& windeployqt `
    --release `
    --compiler-runtime `
    --no-translations `
    --qmldir (Join-Path $repoRoot "app/qml") `
    (Join-Path $binRoot "DiscordVideoApp.exe")
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

$objdump = Join-Path $env:IQTA_TOOLS "mingw1310_64/bin/objdump.exe"
if (-not (Test-Path $objdump)) {
    throw "MinGW objdump.exe was not found"
}
$launcherImports = & $objdump -p (Join-Path $packageRoot "DiscordVideo.exe") 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect the DiscordVideo launcher imports"
}
$externalLauncherRuntime = $launcherImports |
    Select-String -Pattern "Qt6|libgcc|libstdc\+\+|libwinpthread"
if ($externalLauncherRuntime) {
    throw "The DiscordVideo launcher unexpectedly depends on a bundled runtime DLL: $externalLauncherRuntime"
}

$unexpectedRuntimeFilesAtPackageRoot = Get-ChildItem $packageRoot -File |
    Where-Object {
        $_.Extension -eq ".dll" -or
        ($_.Extension -eq ".exe" -and $_.Name -ne "DiscordVideo.exe")
    }
if ($unexpectedRuntimeFilesAtPackageRoot) {
    throw "Unexpected executable or DLL files were placed outside the bin directory"
}

$assetPath = Join-Path $OutputDirectory "Windows-x64_v$Version+$BuildNumber.zip"
Compress-Archive -Path $packageRoot -DestinationPath $assetPath -CompressionLevel Optimal
Write-Output $assetPath
