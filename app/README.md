# DiscordVideo Qt

C++20 と Qt Quick/QML で実装する DiscordVideo の Windows / macOS 版です。

## 必要なもの

- CMake 3.21 以降
- Qt 6.5 以降
  - Qt Core
  - Qt Quick / Qt Quick Controls
  - Qt Multimedia
  - Qt Network
- C++20 対応コンパイラ
- GPL 版の FFmpeg と FFprobe (libx264 対応ビルド)

## ビルド

Qtのインストール先を `CMAKE_PREFIX_PATH` または `Qt6_DIR` で指定してください。

```sh
cmake -S app -B app/build -DCMAKE_BUILD_TYPE=Release
cmake --build app/build --config Release
```

Qt Creator では `app/CMakeLists.txt` を直接開けます。

## FFmpeg

アプリは次の順にFFmpegとFFprobeを検索します。

1. OS のアプリデータディレクトリにある `tools/ffmpeg/current/`
2. DiscordVideo 実行ファイルの隣にある `tools/ffmpeg/`
3. DiscordVideo 実行ファイルと同じディレクトリ
4. `PATH`

Windows では `ffmpeg.exe` と `ffprobe.exe`、macOS では `ffmpeg` と `ffprobe` を配置してください。

自動ダウンロード機能を実装するときも、検証済みのファイルをアプリデータディレクトリの `tools/ffmpeg/current/` へ配置することで、そのまま利用できます。

GitHub Actionsが作成するリリースZIPでは、実行ファイルを基準にした`tools/ffmpeg/`へGPL版の
FFmpegとFFprobeを配置済みです。Windows x64版はBtbN/FFmpeg-Buildsを使用し、macOS arm64版は
FFmpeg 8.1.2とx264をリリース処理内でビルドします。

## 実装済み機能

- ファイル選択とドラッグ＆ドロップ
- JavaFX 版に近い固定サイズのメイン画面
- Qt Multimedia による動画プレビュー
- 再生、一時停止、シーク、トリミング範囲指定
- FFprobe による動画時間取得
- libx264 / AAC による MP4 エンコード
- FFmpeg の進捗表示とキャンセル
- Windows Explorer / macOS Finder での出力ファイル表示
