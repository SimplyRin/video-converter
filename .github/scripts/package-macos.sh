#!/usr/bin/env bash

set -euo pipefail

version="${1:?Version is required}"
build_number="${2:?Build number is required}"
output_dir="${3:?Output directory is required}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
package_root="${RUNNER_TEMP:?RUNNER_TEMP is required}/package/DiscordVideo"
app_source="${repo_root}/build/macos/DiscordVideo.app"
app_bundle="${package_root}/DiscordVideo.app"
ffmpeg_dir="${app_bundle}/Contents/MacOS/tools/ffmpeg"
asset_path="${output_dir}/macOS-arm64_v${version}+${build_number}.zip"

mkdir -p "${package_root}" "${output_dir}"
ditto "${app_source}" "${app_bundle}"
mkdir -p "${ffmpeg_dir}"

bash "${repo_root}/.github/scripts/build-ffmpeg-macos.sh" "${ffmpeg_dir}"

cp "${repo_root}/LICENSE.md" "${package_root}/LICENSE.md"
cp "${repo_root}/THIRD_PARTY_NOTICES.md" "${package_root}/THIRD_PARTY_NOTICES.md"

{
    echo "FFmpeg 8.1.2, built from source for macOS arm64"
    echo "FFmpeg source: https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz"
    echo "x264 commit: b35605ace3ddf7c1a5d67a2eb553f034aef41d55"
    echo
    "${ffmpeg_dir}/ffmpeg" -version | sed -n '1,12p'
} > "${ffmpeg_dir}/BUILD-INFO.txt"

xattr -cr "${app_bundle}"
codesign --force --deep --sign - "${app_bundle}"
codesign --verify --deep --strict --verbose=2 "${app_bundle}"
file "${app_bundle}/Contents/MacOS/DiscordVideo" | grep -F arm64

ditto -c -k --sequesterRsrc --keepParent "${package_root}" "${asset_path}"
echo "${asset_path}"
