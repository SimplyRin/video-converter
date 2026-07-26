// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts

ApplicationWindow {
    id: root

    width: 420
    height: 180
    minimumWidth: 420
    maximumWidth: 420
    minimumHeight: 180
    maximumHeight: 180
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
        messageDialog.messageText = messageText
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

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 8
        anchors.bottomMargin: 10
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 6

            Label {
                Layout.fillWidth: true
                text: "目標のファイルサイズ (MB) を入力してファイルを選択してください"
                font.pixelSize: 12
            }

            Button {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                text: "i"
                flat: true
                font.bold: true
                onClicked: aboutDialog.open()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6

            Label {
                text: "ファイル:"
                font.pixelSize: 12
            }

            Label {
                Layout.fillWidth: true
                text: backend.selectedFileName
                elide: Text.ElideMiddle
                font.pixelSize: 12
            }

            Button {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 28
                text: backend.hasSelectedFile ? "削除" : "選択"
                enabled: !backend.busy
                font.pixelSize: 12
                onClicked: {
                    if (backend.hasSelectedFile)
                        backend.clearSelectedFile()
                    else
                        backend.chooseFile()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 8

            Label {
                text: "目標ファイルサイズ (半角数字):"
                font.pixelSize: 12
            }

            Item {
                Layout.fillWidth: true
            }

            TextField {
                id: targetSize
                Layout.preferredWidth: 82
                Layout.preferredHeight: 30
                enabled: !backend.busy
                horizontalAlignment: TextInput.AlignRight
                placeholderText: "8"
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 99999 }
                font.pixelSize: 12
            }

            Label {
                text: "MB"
                font.pixelSize: 12
            }
        }

        Button {
            id: encodeButton
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            text: backend.busy ? backend.statusText : "エンコード！"
            font.pixelSize: 12
            onClicked: backend.busy ? backend.cancelEncoding() : root.requestEncoding()

            ToolTip.visible: hovered && backend.busy
            ToolTip.text: backend.busy ? "クリックしてキャンセル" : ""
        }

        ProgressBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            from: 0
            to: 1
            value: backend.progress
            opacity: backend.busy ? 1 : 0
        }
    }

    Dialog {
        id: messageDialog
        property string messageText: ""

        anchors.centerIn: parent
        width: 300
        modal: true
        standardButtons: Dialog.Ok

        contentItem: Label {
            width: 270
            wrapMode: Text.WordWrap
            text: messageDialog.messageText
        }
    }

    Dialog {
        id: finishedDialog
        anchors.centerIn: parent
        width: 300
        modal: true
        title: "完了"

        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: backend.revealLatestOutput()

        contentItem: Label {
            width: 270
            wrapMode: Text.WordWrap
            text: "動画のエンコードが完了しました。\n出力ファイルを表示しますか？"
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
