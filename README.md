# DiscordVideo

指定したファイルサイズを目標に、動画をDiscord向けMP4へ変換するデスクトップアプリです。

## ディレクトリ

- `app/` — C++20とQt Quick/QMLによる新しいWindows/macOS版
- `legacy-java/` — 既存のJavaFX版と、そのビルド成果物
- `.github/workflows/release.yml` — タグからWindows/macOS版を作成するリリース処理
- `LICENSE.md` — プロジェクト全体のGNU GPL v3ライセンス
- `THIRD_PARTY_NOTICES.md` — Qt、FFmpeg、x264の配布情報

Qt版はWebViewとXMLを使用しません。画面はQML、アプリケーションロジックはC++で実装しています。

このプロジェクトはGNU General Public License v3.0 or laterで公開します。

ビルド方法とFFmpegの配置方法は[`app/README.md`](app/README.md)を参照してください。

## リリース

`vMAJOR.MINOR.FIX`形式のタグをpushすると、GitHub ActionsがWindows x64版とmacOS arm64版を
ビルドし、同じタグのGitHub Releaseへ次の3ファイルを公開します。

- `Windows-x64_vMAJOR.MINOR.FIX+BUILDNUM.zip`
- `Windows-x64-Setup_vMAJOR.MINOR.FIX+BUILDNUM.exe`
- `macOS-arm64_vMAJOR.MINOR.FIX+BUILDNUM.zip`

`BUILDNUM`は、タグのコミットから辿れる全コミットについて、Gitのnumstatに記録された追加行数を
合計した値です。例えば`cdaf9a3ccb87fd93fe963c536d66089c41958467`では`4091`になります。

両方のZIPにQtランタイム、FFmpeg、FFprobe、ライセンス情報を同梱します。Windows版のGPL
FFmpegはBtbN/FFmpeg-Buildsから取得します。BtbNはmacOSバイナリを提供していないため、macOS版は
Actionsのarm64ランナー上でFFmpegとx264をソースからビルドします。

Windows版の実行ファイルとランタイムは、ZIP内で次のように`bin/`へまとめています。

```text
DiscordVideo/
├── DiscordVideo.exe（起動用）
├── bin/
│   ├── DiscordVideoApp.exe
│   ├── Qt6*.dll
│   ├── platforms、qmlなどのQtランタイム
│   └── tools/ffmpeg/（ffmpeg.exe、ffprobe.exe）
├── LICENSE.md
└── THIRD_PARTY_NOTICES.md
```

Windowsではルートディレクトリの`DiscordVideo.exe`を起動してください。

WindowsのSetup版は、Program Filesへのインストール、スタートメニュー登録、任意のデスクトップ
ショートカット作成、アンインストールに対応します。ポータブルZIP版も引き続き公開します。

### ブランチの手動ビルド

GitHubのActions画面で`Build and release`を開き、`Run workflow`から対象ブランチを選択すると、
そのブランチをプリリリースとしてビルド・公開します。リポジトリの最新の安定版タグとコミットSHAの
先頭7桁を使い、`vMAJOR.MINOR.FIX-PRE_COMMIT`形式のGitタグを作成します。

例えば、最新の安定版タグが`v1.0.9`、対象コミットが`d2e8f98...`の場合、GitHub Releaseのタグは
`v1.0.9-PRE_d2e8f98`となり、Pre-releaseとして公開されます。配布ファイルとアプリ本体の完全
バージョンには、従来どおり`calculate-build-number.sh`の`BUILDNUM`も加わります。
