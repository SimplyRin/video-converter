// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts

ApplicationWindow {
    id: mixerWindow

    width: 720
    height: 460
    minimumWidth: 620
    minimumHeight: 380
    visible: false
    flags: Qt.Dialog
    title: "音量ミキサー"
    color: palette.window

    function openMixer() {
        show()
        raise()
        requestActivate()
    }

    function selectedAudioCount() {
        let count = 0
        const tracks = backend.audioTracks
        for (let index = 0; index < tracks.length; ++index) {
            if (tracks[index].selected)
                ++count
        }
        return count
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Label {
            Layout.fillWidth: true
            text: "出力へ合成する音声トラックと、トラックごとの音量を調整します。"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: mixerWindow.palette.base
            border.color: mixerWindow.palette.mid
            radius: 3

            ListView {
                id: trackList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                spacing: 1
                model: backend.audioTracks

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: trackList.width
                    height: 84
                    color: index % 2 === 0 ? mixerWindow.palette.alternateBase
                                           : mixerWindow.palette.base

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        CheckBox {
                            id: enabledCheck
                            checked: modelData.selected
                            enabled: !backend.busy && !backend.analyzingAudio
                            onToggled: backend.setAudioTrackSelected(modelData.index, checked)
                            Accessible.name: modelData.label + " を出力に含める"
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 225
                            Layout.maximumWidth: 225
                            spacing: 3

                            Label {
                                Layout.fillWidth: true
                                text: modelData.label
                                elide: Text.ElideRight
                                font.bold: true
                            }

                            Label {
                                Layout.fillWidth: true
                                text: modelData.hasMeasurement
                                      ? "測定平均: " + Number(modelData.meanVolumeDb).toFixed(1)
                                        + " dBFS / 補正後: "
                                        + Number(modelData.meanVolumeDb + gainSlider.value).toFixed(1) + " dBFS"
                                      : "平均音量: 未測定"
                                font.pixelSize: 11
                                opacity: 0.75
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: modelData.hasRecommendation
                                text: "おすすめゲイン: "
                                      + (modelData.recommendedGainDb >= 0 ? "+" : "")
                                      + Number(modelData.recommendedGainDb).toFixed(1) + " dB"
                                color: mixerWindow.palette.highlight
                                font.pixelSize: 11
                                font.bold: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8
                                color: "#252525"
                                radius: 2

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1,
                                           ((modelData.hasMeasurement
                                             ? modelData.meanVolumeDb + gainSlider.value
                                             : -60) + 60) / 60))
                                    height: parent.height
                                    radius: 2
                                    color: width > parent.width * 0.9 ? "#ef5350"
                                          : (width > parent.width * 0.75 ? "#fbc02d" : "#43a047")
                                }
                            }
                        }

                        Label {
                            text: "-30"
                            font.pixelSize: 10
                            opacity: 0.65
                        }

                        Slider {
                            id: gainSlider
                            Layout.fillWidth: true
                            from: -30
                            to: 30
                            stepSize: 0.5
                            value: modelData.gainDb
                            enabled: modelData.selected && !backend.busy && !backend.analyzingAudio
                            onMoved: {
                                if (!pressed)
                                    backend.setAudioTrackGainDb(modelData.index, value)
                            }
                            onPressedChanged: {
                                if (!pressed)
                                    backend.setAudioTrackGainDb(modelData.index, value)
                            }
                            Accessible.name: modelData.label + " のゲイン"
                        }

                        Label {
                            text: "+30"
                            font.pixelSize: 10
                            opacity: 0.65
                        }

                        Label {
                            Layout.preferredWidth: 62
                            horizontalAlignment: Text.AlignRight
                            text: (gainSlider.value >= 0 ? "+" : "")
                                  + Number(gainSlider.value).toFixed(1) + " dB"
                            font.family: "monospace"
                        }

                        Button {
                            text: modelData.hasRecommendation ? "おすすめ" : "0 dB"
                            enabled: !backend.busy && !backend.analyzingAudio
                            onClicked: backend.setAudioTrackGainDb(
                                           modelData.index,
                                           modelData.hasRecommendation
                                           ? modelData.recommendedGainDb : 0)
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: trackList.count === 0
                    text: backend.tracksLoading ? "音声トラックを解析中…" : "音声トラックがありません。"
                    opacity: 0.7
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "自動調整の目標:"
            }

            TextField {
                id: targetLevel
                Layout.preferredWidth: 72
                text: "-8.0"
                horizontalAlignment: TextInput.AlignRight
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: DoubleValidator {
                    bottom: -30
                    top: 0
                    decimals: 1
                    notation: DoubleValidator.StandardNotation
                }
                enabled: !backend.analyzingAudio && !backend.busy
            }

            Label {
                text: "dBFS"
            }

            Label {
                text: "おすすめ: -8 dBFS"
                color: mixerWindow.palette.highlight
                font.bold: true
            }

            Button {
                text: backend.analyzingAudio ? "解析中…" : "自動"
                highlighted: true
                enabled: !backend.analyzingAudio && !backend.busy
                         && mixerWindow.selectedAudioCount() > 0
                         && targetLevel.acceptableInput
                onClicked: backend.autoAdjustAudioTracks(
                               Number.fromLocaleString(Qt.locale(), targetLevel.text))

                ToolTip.visible: hovered
                ToolTip.text: "選択した各トラックの平均音量を測定し、おすすめゲインを算出・適用します。"
            }

            BusyIndicator {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                running: backend.analyzingAudio
                visible: running
            }

            Label {
                Layout.fillWidth: true
                text: backend.audioAnalysisStatus
                elide: Text.ElideRight
                font.pixelSize: 11
                opacity: 0.8
            }

            Button {
                text: "閉じる"
                onClicked: mixerWindow.close()
            }
        }

        Label {
            Layout.fillWidth: true
            text: "-8 dBFS は実用的な既定値です。素材に合わせて -30～0 dBFS の範囲で変更できます。複数選択時は合成後の推定平均が目標へ近づくよう配分し、ピーク超過は出力時にリミッターで抑制します。"
            wrapMode: Text.WordWrap
            font.pixelSize: 10
            opacity: 0.65
        }
    }
}
