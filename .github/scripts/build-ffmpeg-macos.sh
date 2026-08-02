#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ffmpeg-macos-versions.env
source "${script_dir}/ffmpeg-macos-versions.env"

validation_only="false"
if [[ "${1:-}" == "--validate" ]]; then
    validation_only="true"
    shift
fi
output_dir="${1:?Output directory is required}"
manifest_path="${output_dir}/.discordvideo-ffmpeg-cache-manifest"
script_sha256="$(shasum -a 256 "$0" | awk '{print $1}')"
cache_identity="schema=${FFMPEG_CACHE_SCHEMA};ffmpeg=${FFMPEG_VERSION};ffmpeg_sha256=${FFMPEG_SHA256};x264=${X264_COMMIT};deployment=${FFMPEG_MACOS_DEPLOYMENT_TARGET};arch=arm64;script=${script_sha256}"

validate_output() {
    [[ -f "${manifest_path}" ]] || return 1
    [[ "$(<"${manifest_path}")" == "${cache_identity}" ]] || return 1
    [[ -x "${output_dir}/ffmpeg" && -x "${output_dir}/ffprobe" ]] || return 1
    [[ -f "${output_dir}/FFmpeg-COPYING.GPLv3" ]] || return 1
    [[ -f "${output_dir}/x264-COPYING" ]] || return 1
    for binary in ffmpeg ffprobe; do
        file "${output_dir}/${binary}" | grep -F arm64 >/dev/null || return 1
    done
    "${output_dir}/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -F libx264 >/dev/null || return 1
    "${output_dir}/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -F h264_videotoolbox >/dev/null || return 1
    "${output_dir}/ffmpeg" -version 2>/dev/null | sed -n '1p' | grep -F "ffmpeg version ${FFMPEG_VERSION}" >/dev/null || return 1
    "${output_dir}/ffprobe" -version 2>/dev/null | sed -n '1p' | grep -F "ffprobe version ${FFMPEG_VERSION}" >/dev/null || return 1
}

if validate_output; then
    echo "Using cached FFmpeg ${FFMPEG_VERSION} / x264 ${X264_COMMIT} from ${output_dir}."
    exit 0
fi

if [[ "${validation_only}" == "true" ]]; then
    echo "A valid cached FFmpeg build was not found in ${output_dir}."
    exit 1
fi

work_root="$(mktemp -d "${RUNNER_TEMP:?RUNNER_TEMP is required}/discordvideo-ffmpeg-build.XXXXXX")"
x264_source="${work_root}/x264"
x264_prefix="${work_root}/x264-install"
ffmpeg_source="${work_root}/ffmpeg-${FFMPEG_VERSION}"
ffmpeg_prefix="${work_root}/ffmpeg-install"
ffmpeg_archive="${work_root}/ffmpeg-${FFMPEG_VERSION}.tar.xz"
trap 'rm -rf "${work_root}"' EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "The macOS release must be built on an arm64 runner." >&2
    exit 1
fi

mkdir -p "${work_root}" "${output_dir}"
rm -f "${manifest_path}" \
    "${output_dir}/ffmpeg" \
    "${output_dir}/ffprobe" \
    "${output_dir}/FFmpeg-COPYING.GPLv3" \
    "${output_dir}/x264-COPYING"

git clone --filter=blob:none https://code.videolan.org/videolan/x264.git "${x264_source}"
git -C "${x264_source}" checkout --detach "${X264_COMMIT}"

export MACOSX_DEPLOYMENT_TARGET="${FFMPEG_MACOS_DEPLOYMENT_TARGET}"

(
    cd "${x264_source}"
    ./configure \
        --prefix="${x264_prefix}" \
        --enable-static \
        --enable-pic \
        --disable-cli \
        --disable-opencl
    make -j "$(sysctl -n hw.ncpu)"
    make install
)

curl --proto '=https' --tlsv1.2 --fail --location --retry 5 \
    --output "${ffmpeg_archive}" \
    "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
echo "${FFMPEG_SHA256}  ${ffmpeg_archive}" | shasum -a 256 --check
tar -C "${work_root}" -xf "${ffmpeg_archive}"

(
    cd "${ffmpeg_source}"
    PKG_CONFIG_PATH="${x264_prefix}/lib/pkgconfig" ./configure \
        --prefix="${ffmpeg_prefix}" \
        --cc=clang \
        --pkg-config-flags=--static \
        --extra-cflags="-I${x264_prefix}/include" \
        --extra-ldflags="-L${x264_prefix}/lib" \
        --enable-gpl \
        --enable-version3 \
        --enable-libx264 \
        --enable-videotoolbox \
        --enable-static \
        --disable-shared \
        --disable-autodetect \
        --disable-debug \
        --disable-doc \
        --disable-ffplay \
        --disable-network
    make -j "$(sysctl -n hw.ncpu)"
    make install
)

cp "${ffmpeg_prefix}/bin/ffmpeg" "${output_dir}/ffmpeg"
cp "${ffmpeg_prefix}/bin/ffprobe" "${output_dir}/ffprobe"
cp "${ffmpeg_source}/COPYING.GPLv3" "${output_dir}/FFmpeg-COPYING.GPLv3"
cp "${x264_source}/COPYING" "${output_dir}/x264-COPYING"
chmod 755 "${output_dir}/ffmpeg" "${output_dir}/ffprobe"

if otool -L "${output_dir}/ffmpeg" "${output_dir}/ffprobe" | grep -F "${work_root}"; then
    echo "FFmpeg contains a build-directory dependency." >&2
    exit 1
fi

"${output_dir}/ffmpeg" -hide_banner -encoders | grep -F libx264
"${output_dir}/ffmpeg" -hide_banner -encoders | grep -F h264_videotoolbox
"${output_dir}/ffprobe" -version | sed -n '1p'

printf '%s\n' "${cache_identity}" > "${manifest_path}"
if ! validate_output; then
    rm -f "${manifest_path}"
    echo "The completed FFmpeg build did not pass cache validation." >&2
    exit 1
fi

echo "FFmpeg build cache prepared at ${output_dir}."
