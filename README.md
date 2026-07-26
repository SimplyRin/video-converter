# DiscordVideo

指定したファイルサイズを目標に、動画をDiscord向けMP4へ変換するデスクトップアプリです。

## ディレクトリ

- `app/` — C++20とQt Quick/QMLによる新しいWindows/macOS版
- `legacy-java/` — 既存のJavaFX版と、そのビルド成果物
- `LICENSE.md` — プロジェクト全体のGNU GPL v3ライセンス

Qt版はWebViewとXMLを使用しません。画面はQML、アプリケーションロジックはC++で実装しています。

このプロジェクトはGNU General Public License v3.0 or laterで公開します。

ビルド方法とFFmpegの配置方法は[`app/README.md`](app/README.md)を参照してください。
