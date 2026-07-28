// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import QtMultimedia

ApplicationWindow {
    id: trimWindow

    width: 681
    height: 680
    minimumWidth: 681
    maximumWidth: 681
    minimumHeight: 680
    maximumHeight: 680
    visible: false
    modality: Qt.ApplicationModal
    flags: Qt.Dialog
    title: "動画のトリミング"
    color: palette.window

    property int targetSizeMiB: 8
    property double startPosition: -1
    property double endPosition: -1

    function openVideo(url, targetSize) {
        targetSizeMiB = targetSize
        startPosition = -1
        endPosition = -1
        validationText.text = ""
        player.source = url
        show()
        raise()
        requestActivate()
        player.play()
    }

    onClosing: function(close) {
        player.stop()
        player.source = ""
    }

    AudioOutput {
        id: audioOutput
        volume: 0.05
    }

    MediaPlayer {
        id: player
        audioOutput: audioOutput
        videoOutput: videoOutput

        onErrorOccurred: function(error, errorString) {
            validationText.text = "動画を再生できません: " + errorString
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: "トリミングしない場合は、そのまま「エンコード」を押してください。"
            font.pixelSize: 13
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: player.playbackState === MediaPlayer.PlayingState ? "一時停止" : "再生"
                onClicked: {
                    if (player.playbackState === MediaPlayer.PlayingState)
                        player.pause()
                    else
                        player.play()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: "開始位置に設定"
                onClicked: {
                    trimWindow.startPosition = player.position
                    if (trimWindow.endPosition >= 0 && trimWindow.endPosition <= trimWindow.startPosition)
                        trimWindow.endPosition = -1
                }
            }

            Label {
                text: "開始位置: " + (trimWindow.startPosition < 0 ? "未設定" : formatTime(trimWindow.startPosition))
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: "終了位置に設定"
                onClicked: {
                    if (trimWindow.startPosition < 0) {
                        validationText.text = "先に開始位置を設定してください。"
                        return
                    }
                    if (player.position <= trimWindow.startPosition) {
                        validationText.text = "終了位置は開始位置より後に設定してください。"
                        return
                    }
                    trimWindow.endPosition = player.position
                    validationText.text = ""
                }
            }

            Label {
                text: "終了位置: " + (trimWindow.endPosition < 0 ? "未設定" : formatTime(trimWindow.endPosition))
            }

            Item { Layout.fillWidth: true }
        }

        Slider {
            id: seekSlider
            Layout.fillWidth: true
            from: 0
            to: Math.max(1, player.duration)
            value: player.position
            onMoved: player.position = value
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: formatTime(player.position) + " / " + formatTime(player.duration)
            font.pixelSize: 11
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#111111"
            border.color: trimWindow.palette.mid

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                anchors.margins: 1
                fillMode: VideoOutput.PreserveAspectFit
            }
        }

        Label {
            id: validationText
            Layout.fillWidth: true
            color: trimWindow.palette.window.hslLightness < 0.5 ? "#ff8a8a" : "#b00020"
            wrapMode: Text.WordWrap
            visible: text.length > 0
        }

        CheckBox {
            id: preferHardwareEncoder
            text: "可能であれば GPU エンコードを使用する"
            checked: true

            ToolTip.visible: hovered
            ToolTip.text: "利用できない場合は自動的に CPU エンコードへ切り替えます。"
        }

        CheckBox {
            id: deleteCacheAfterEncoding
            text: "エンコード完了後に一時ファイルを削除する"
            checked: false
            enabled: trimWindow.startPosition >= 0 && trimWindow.endPosition >= 0

            ToolTip.visible: hovered
            ToolTip.text: "トリミング範囲を指定した場合に作成される一時MP4が対象です。"
        }

        Label {
            Layout.fillWidth: true
            text: "一時ファイルは、指定したトリミング範囲を再エンコードせずに保存した無劣化動画です。元動画と同じフォルダーに保存されます。"
            wrapMode: Text.WordWrap
            font.pixelSize: 11
            opacity: 0.75
        }

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            Button {
                text: "キャンセル"
                onClicked: trimWindow.close()
            }

            Button {
                text: "エンコード"
                highlighted: true
                onClicked: {
                    const hasStart = trimWindow.startPosition >= 0
                    const hasEnd = trimWindow.endPosition >= 0
                    if (hasStart !== hasEnd) {
                        validationText.text = "トリミングする場合は開始位置と終了位置の両方を設定してください。"
                        return
                    }
                    if (hasStart && trimWindow.endPosition <= trimWindow.startPosition) {
                        validationText.text = "終了位置は開始位置より後に設定してください。"
                        return
                    }

                    player.stop()
                    backend.encode(trimWindow.targetSizeMiB,
                                   hasStart ? Math.round(trimWindow.startPosition) : -1,
                                   hasEnd ? Math.round(trimWindow.endPosition) : -1,
                                   preferHardwareEncoder.checked,
                                   deleteCacheAfterEncoding.checked)
                    trimWindow.close()
                }
            }
        }
    }

    function formatTime(milliseconds) {
        if (!Number.isFinite(milliseconds) || milliseconds < 0)
            milliseconds = 0
        const totalSeconds = Math.floor(milliseconds / 1000)
        const hours = Math.floor(totalSeconds / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const seconds = totalSeconds % 60
        return String(hours).padStart(2, "0") + ":"
             + String(minutes).padStart(2, "0") + ":"
             + String(seconds).padStart(2, "0")
    }
}
