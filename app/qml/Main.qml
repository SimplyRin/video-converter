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
    color: palette.window

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
                id: informationButton
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                text: "i"
                flat: true
                font.bold: true
                onClicked: aboutWindow.showSection(backend.updateAvailable ? 1 : 0)
                Accessible.name: backend.updateAvailable
                                 ? "アップデートがあります。アプリ情報を開く"
                                 : "アプリ情報を開く"

                property real updatePulse: 0.35

                SequentialAnimation on updatePulse {
                    running: backend.updateAvailable
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.3; to: 0.85; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.85; to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                }

                background: Rectangle {
                    radius: width / 2
                    color: backend.updateAvailable
                           ? "#ff9800"
                           : (informationButton.hovered ? root.palette.button : "transparent")
                    opacity: backend.updateAvailable ? informationButton.updatePulse : 1
                    border.width: backend.updateAvailable ? 2 : 0
                    border.color: "#ffc107"
                }

                contentItem: Label {
                    text: informationButton.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: informationButton.font
                    color: root.palette.windowText
                }

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    anchors.top: parent.top
                    anchors.right: parent.right
                    color: "#ff5252"
                    border.width: 1
                    border.color: root.palette.window
                    visible: backend.updateAvailable
                }

                ToolTip.visible: hovered
                ToolTip.text: backend.updateAvailable
                              ? backend.latestVersion + " が利用できます"
                              : (backend.checkingForUpdates ? "アップデートを確認中..." : "アプリ情報")
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
                placeholderText: "10"
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

    AboutWindow {
        id: aboutWindow
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

    Component.onCompleted: backend.checkForUpdates()
}
