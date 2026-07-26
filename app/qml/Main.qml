// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

ApplicationWindow {
    id: root

    width: 327
    height: 138
    minimumWidth: 327
    maximumWidth: 327
    minimumHeight: 138
    maximumHeight: 138
    visible: true
    title: "DiscordVideo"
    color: "#f4f4f4"

    function requestEncoding() {
        if (!backend.hasSelectedFile) {
            showMessage("エラー", "ファイルを選択してください。")
            return
        }

        const size = Number(targetSize.text.length === 0 ? targetSize.placeholderText : targetSize.text)
        if (!Number.isInteger(size) || size <= 0) {
            showMessage("構文エラー", "目標ファイルサイズには 1 以上の整数を入力してください。")
            return
        }

        trimWindow.openVideo(backend.selectedFileUrl, size)
    }

    function showMessage(messageTitle, messageText) {
        messageDialog.title = messageTitle
        messageDialog.text = messageText
        messageDialog.open()
    }

    palette.window: "#f4f4f4"
    palette.windowText: "#202020"
    palette.button: "#f5f5f5"
    palette.buttonText: "#202020"
    palette.base: "#ffffff"
    palette.text: "#202020"
    palette.highlight: "#0096c9"
    palette.highlightedText: "#ffffff"

    DropArea {
        anchors.fill: parent
        onDropped: function(drop) {
            if (drop.hasUrls && drop.urls.length > 0)
                backend.selectFile(drop.urls[0])
        }
    }

    Text {
        x: 14
        y: 12
        text: "目標のファイルサイズ (MB) を入力してファイルを選択してください"
        font.pixelSize: 12
        color: "#202020"
    }

    Label {
        x: 14
        y: 35
        text: "ファイル:"
        font.pixelSize: 12
    }

    Label {
        x: 60
        y: 35
        width: 200
        text: backend.selectedFileName
        elide: Text.ElideMiddle
        font.pixelSize: 12
    }

    Button {
        x: 266
        y: 31
        width: 48
        height: 25
        text: backend.hasSelectedFile ? "削除" : "選択"
        enabled: !backend.busy
        font.pixelSize: 12
        onClicked: {
            if (backend.hasSelectedFile)
                backend.clearSelectedFile()
            else
                fileDialog.open()
        }
    }

    Label {
        x: 14
        y: 67
        text: "目標ファイルサイズ (半角数字):"
        font.pixelSize: 12
    }

    TextField {
        id: targetSize
        x: 167
        y: 62
        width: 109
        height: 27
        enabled: !backend.busy
        horizontalAlignment: TextInput.AlignRight
        placeholderText: "8"
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: 1; top: 99999 }
        font.pixelSize: 12
    }

    Label {
        x: 286
        y: 67
        text: "MB"
        font.pixelSize: 12
    }

    Button {
        id: encodeButton
        x: 14
        y: 96
        width: 300
        height: 27
        text: backend.busy ? backend.statusText : "エンコード！"
        font.pixelSize: 12
        onClicked: backend.busy ? backend.cancelEncoding() : root.requestEncoding()

        ToolTip.visible: hovered && backend.busy
        ToolTip.text: backend.busy ? "クリックしてキャンセル" : ""
    }

    ProgressBar {
        x: 14
        y: 125
        width: 300
        height: 4
        from: 0
        to: 1
        value: backend.progress
        visible: backend.busy
    }

    Button {
        x: 302
        y: 2
        width: 20
        height: 20
        text: "i"
        flat: true
        font.bold: true
        onClicked: aboutDialog.open()
    }

    FileDialog {
        id: fileDialog
        title: "動画ファイルを選択"
        nameFilters: ["動画ファイル (*.mp4 *.mkv *.mov *.avi *.webm *.m4v)", "すべてのファイル (*)"]
        onAccepted: backend.selectFile(selectedFile)
    }

    MessageDialog {
        id: messageDialog
        buttons: MessageDialog.Ok
    }

    MessageDialog {
        id: finishedDialog
        title: "完了"
        text: "動画のエンコードが完了しました。"
        informativeText: "出力ファイルを表示しますか？"
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (button === MessageDialog.Yes)
                backend.revealLatestOutput()
        }
    }

    Dialog {
        id: aboutDialog
        anchors.centerIn: parent
        width: 300
        modal: true
        title: "Open Source Info"
        standardButtons: Dialog.Ok

        contentItem: Label {
            width: 270
            wrapMode: Text.WordWrap
            text: "DiscordVideo\n\nGNU General Public License v3.0 or later\n\nエンコード機能には GPL 版 FFmpeg を使用します。"
        }
    }

    TrimWindow {
        id: trimWindow
    }

    Connections {
        target: backend

        function onErrorOccurred(errorTitle, message) {
            root.showMessage(errorTitle, message)
        }

        function onEncodingFinished(outputPath) {
            finishedDialog.open()
        }
    }
}
