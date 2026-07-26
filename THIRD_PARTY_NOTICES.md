# Third-party notices

DiscordVideo release archives include third-party runtime components. DiscordVideo itself is
distributed under the GNU General Public License version 3 or later; see `LICENSE.md`.

## Qt

The desktop application uses Qt 6, including Qt Core, GUI, Widgets, QML, Quick, Quick Controls,
Network, and Multimedia. Qt is available under the GNU General Public License version 3 and other
commercial/open-source license options.

- Project: https://www.qt.io/
- Source: https://code.qt.io/cgit/qt/
- License information: https://www.qt.io/licensing/open-source-lgpl-obligations

## FFmpeg and x264

The release archives include `ffmpeg` and `ffprobe` built with GPL components, including x264.
These binaries are distributed under the applicable GNU GPL terms. The `nonfree` FFmpeg variant is
not used.

- FFmpeg project and source: https://ffmpeg.org/
- FFmpeg license information: https://ffmpeg.org/legal.html
- x264 project and source: https://code.videolan.org/videolan/x264

The Windows x64 archive uses the GPL static build published by BtbN/FFmpeg-Builds:

- Build project and source recipes: https://github.com/BtbN/FFmpeg-Builds
- Release assets: https://github.com/BtbN/FFmpeg-Builds/releases/tag/latest

The macOS arm64 archive uses FFmpeg 8.1.2 and x264 commit
`b35605ace3ddf7c1a5d67a2eb553f034aef41d55`, compiled by the release workflow. Its FFmpeg and x264
license texts are included beside the executables.
