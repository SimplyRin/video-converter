#!/usr/bin/env bash

set -euo pipefail

output_dir="${1:?Output directory is required}"
work_root="$(mktemp -d "${RUNNER_TEMP:?RUNNER_TEMP is required}/discordvideo-ffmpeg-build.XXXXXX")"
x264_source="${work_root}/x264"
x264_prefix="${work_root}/x264-install"
ffmpeg_source="${work_root}/ffmpeg-8.1.2"
ffmpeg_prefix="${work_root}/ffmpeg-install"
ffmpeg_archive="${work_root}/ffmpeg-8.1.2.tar.xz"

ffmpeg_sha256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
x264_commit="b35605ace3ddf7c1a5d67a2eb553f034aef41d55"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "The macOS release must be built on an arm64 runner." >&2
    exit 1
fi

mkdir -p "${work_root}" "${output_dir}"

git clone --filter=blob:none https://code.videolan.org/videolan/x264.git "${x264_source}"
git -C "${x264_source}" checkout --detach "${x264_commit}"

export MACOSX_DEPLOYMENT_TARGET=13.0

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
    https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
echo "${ffmpeg_sha256}  ${ffmpeg_archive}" | shasum -a 256 --check
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
