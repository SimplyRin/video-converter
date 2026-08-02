#!/usr/bin/env bash

set -euo pipefail

version="${1:?Version is required}"
output_dir="${2:?Output directory is required}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
ffmpeg_cache_dir="${3:-${RUNNER_TEMP:?RUNNER_TEMP is required}/discordvideo-ffmpeg-cache/macos-arm64}"
# shellcheck source=ffmpeg-macos-versions.env
source "${repo_root}/.github/scripts/ffmpeg-macos-versions.env"
package_root="${RUNNER_TEMP:?RUNNER_TEMP is required}/package/DiscordVideo"
app_source="${repo_root}/build/macos/DiscordVideo.app"
app_bundle="${package_root}/DiscordVideo.app"
ffmpeg_dir="${app_bundle}/Contents/MacOS/tools/ffmpeg"
asset_path="${output_dir}/macOS-arm64_v${version}.zip"

mkdir -p "${package_root}" "${output_dir}"
ditto "${app_source}" "${app_bundle}"
mkdir -p "${ffmpeg_dir}"

icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${app_bundle}/Contents/Info.plist")"
if [[ "${icon_name}" != "DiscordVideo.icns" \
    || ! -f "${app_bundle}/Contents/Resources/${icon_name}" ]]; then
    echo "The macOS application icon is missing from the app bundle." >&2
    exit 1
fi

bash "${repo_root}/.github/scripts/build-ffmpeg-macos.sh" "${ffmpeg_cache_dir}"
bash "${repo_root}/.github/scripts/build-ffmpeg-macos.sh" --validate "${ffmpeg_cache_dir}"
cp "${ffmpeg_cache_dir}/ffmpeg" "${ffmpeg_dir}/ffmpeg"
cp "${ffmpeg_cache_dir}/ffprobe" "${ffmpeg_dir}/ffprobe"
cp "${ffmpeg_cache_dir}/FFmpeg-COPYING.GPLv3" "${ffmpeg_dir}/FFmpeg-COPYING.GPLv3"
cp "${ffmpeg_cache_dir}/x264-COPYING" "${ffmpeg_dir}/x264-COPYING"
chmod 755 "${ffmpeg_dir}/ffmpeg" "${ffmpeg_dir}/ffprobe"

cp "${repo_root}/LICENSE.md" "${package_root}/LICENSE.md"
cp "${repo_root}/THIRD_PARTY_NOTICES.md" "${package_root}/THIRD_PARTY_NOTICES.md"

{
    echo "FFmpeg ${FFMPEG_VERSION}, built from source for macOS arm64"
    echo "FFmpeg source: https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    echo "FFmpeg SHA-256: ${FFMPEG_SHA256}"
    echo "x264 commit: ${X264_COMMIT}"
    echo
    "${ffmpeg_dir}/ffmpeg" -version | sed -n '1,12p'
} > "${ffmpeg_dir}/BUILD-INFO.txt"

xattr -cr "${app_bundle}"
codesign --force --deep --sign - "${app_bundle}"
codesign --verify --deep --strict --verbose=2 "${app_bundle}"
file "${app_bundle}/Contents/MacOS/DiscordVideo" | grep -F arm64

ditto -c -k --sequesterRsrc --keepParent "${package_root}" "${asset_path}"
echo "${asset_path}"
