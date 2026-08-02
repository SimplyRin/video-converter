// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts

ApplicationWindow {
    id: mixerWindow

    width: 800
    height: 650
    minimumWidth: 720
    minimumHeight: 560
    visible: false
    flags: Qt.Dialog
    title: "音量ミキサー"
    color: palette.window
    property bool previewPlaying: false
    property var waveformLevels: []

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

    function liveLevelDb(trackIndex) {
        const levels = backend.audioTrackLevels
        return trackIndex >= 0 && trackIndex < levels.length
               ? Number(levels[trackIndex]) : -60
    }

    function isTrackPreviewed(trackIndex, selected) {
        return backend.monitoredAudioTrack >= 0
               ? backend.monitoredAudioTrack === trackIndex : selected
    }

    function monitoredLevelDb() {
        if (backend.monitoredAudioTrack >= 0)
            return liveLevelDb(backend.monitoredAudioTrack)

        const tracks = backend.audioTracks
        let amplitude = 0
        for (let index = 0; index < tracks.length; ++index) {
            if (tracks[index].selected)
                amplitude += Math.pow(10, liveLevelDb(index) / 20)
        }
        return amplitude > 0 ? Math.min(0, 20 * Math.log10(amplitude)) : -60
    }

    function appendWaveformLevel() {
        const history = waveformLevels.slice()
        history.push(monitoredLevelDb())
        if (history.length > 320)
            history.splice(0, history.length - 320)
        waveformLevels = history
        waveformCanvas.requestPaint()
    }

    function clearWaveform() {
        waveformLevels = []
        waveformCanvas.requestPaint()
    }

    onPreviewPlayingChanged: {
        if (!previewPlaying)
            clearWaveform()
    }

    Connections {
        target: backend
        function onAudioMonitorChanged() { mixerWindow.clearWaveform() }
    }

    Timer {
        interval: 50
        repeat: true
        running: mixerWindow.visible && mixerWindow.previewPlaying
        onTriggered: mixerWindow.appendWaveformLevel()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: "出力へ合成するトラックを選択し、音量とモニターを調整します。"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Button {
                text: "すべて選択"
                enabled: !backend.busy && !backend.analyzingAudio
                         && backend.audioTracks.length > 0
                onClicked: backend.setAllAudioTracksSelected(true)
            }

            Button {
                text: "すべて解除"
                enabled: !backend.busy && !backend.analyzingAudio
                         && backend.audioTracks.length > 0
                onClicked: backend.setAllAudioTracksSelected(false)
            }

            Button {
                text: "ミックスをモニター"
                visible: backend.monitoredAudioTrack >= 0
                onClicked: backend.setMonitoredAudioTrack(-1)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            color: "#17131b"
            border.color: backend.monitoredAudioTrack >= 0 ? "#ec64a5" : "#66606a"
            radius: 4
            clip: true

            Label {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 7
                z: 2
                text: backend.monitoredAudioTrack >= 0
                      ? "音声トラック " + backend.monitoredAudioTrack + " をモニター中"
                      : "選択トラックのミックスをモニター中"
                color: "white"
                font.pixelSize: 11
            }

            Label {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 7
                z: 2
                text: mixerWindow.previewPlaying
                      ? Number(mixerWindow.monitoredLevelDb()).toFixed(1) + " dBFS"
                      : "-- dBFS"
                color: "white"
                font.family: "monospace"
            }

            Canvas {
                id: waveformCanvas
                anchors.fill: parent
                anchors.topMargin: 20

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const context = getContext("2d")
                    context.reset()
                    context.clearRect(0, 0, width, height)

                    const center = height / 2
                    context.strokeStyle = "#554b58"
                    context.lineWidth = 1
                    context.beginPath()
                    context.moveTo(0, center)
                    context.lineTo(width, center)
                    context.stroke()

                    const values = mixerWindow.waveformLevels
                    if (values.length < 2)
                        return

                    const step = width / Math.max(1, values.length - 1)
                    context.beginPath()
                    for (let index = 0; index < values.length; ++index) {
                        const normalized = Math.max(0, Math.min(1,
                                                   (Number(values[index]) + 60) / 60))
                        const y = center - normalized * (center - 4)
                        if (index === 0)
                            context.moveTo(0, y)
                        else
                            context.lineTo(index * step, y)
                    }
                    for (let index = values.length - 1; index >= 0; --index) {
                        const normalized = Math.max(0, Math.min(1,
                                                   (Number(values[index]) + 60) / 60))
                        context.lineTo(index * step, center + normalized * (center - 4))
                    }
                    context.closePath()
                    context.fillStyle = "rgba(236, 100, 165, 0.22)"
                    context.fill()
                    context.strokeStyle = "#ffffff"
                    context.lineWidth = 1.5
                    context.stroke()
                }
            }
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
                    height: 104
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
                            Layout.preferredWidth: 210
                            Layout.maximumWidth: 210
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

                            Label {
                                Layout.fillWidth: true
                                text: mixerWindow.previewPlaying
                                      && mixerWindow.isTrackPreviewed(modelData.index,
                                                                      modelData.selected)
                                      ? "再生レベル: "
                                        + Number(mixerWindow.liveLevelDb(modelData.index)).toFixed(1)
                                        + " dBFS"
                                      : "再生レベル: -- dBFS"
                                font.pixelSize: 11
                                font.bold: mixerWindow.previewPlaying
                                           && mixerWindow.isTrackPreviewed(modelData.index,
                                                                           modelData.selected)
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8
                                color: "#252525"
                                radius: 2

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1,
                                           ((mixerWindow.previewPlaying
                                             && mixerWindow.isTrackPreviewed(modelData.index,
                                                                             modelData.selected)
                                             ? mixerWindow.liveLevelDb(modelData.index)
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

                        Button {
                            Layout.preferredWidth: 76
                            text: checked ? "モニター中" : "モニター"
                            checkable: true
                            checked: backend.monitoredAudioTrack === modelData.index
                            enabled: modelData.selected && !backend.busy
                            onClicked: backend.setMonitoredAudioTrack(
                                           checked ? modelData.index : -1)

                            ToolTip.visible: hovered
                            ToolTip.text: modelData.selected
                                          ? "選択中のこのトラックだけをプレビューします。"
                                          : "先にこのトラックを出力対象としてチェックしてください。"
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
                         && backend.audioTracks.length > 0
                         && targetLevel.acceptableInput
                onClicked: {
                    analysisScopeDialog.targetDb = Number.fromLocaleString(
                                                       Qt.locale(), targetLevel.text)
                    analysisScopeDialog.open()
                }

                ToolTip.visible: hovered
                ToolTip.text: "全トラックまたは現在チェック済みのトラックを解析します。"
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

        ProgressBar {
            Layout.fillWidth: true
            visible: backend.analyzingAudio
            from: 0
            to: 1
            value: backend.audioAnalysisTrackProgress
        }

        Label {
            Layout.fillWidth: true
            text: "-8 dBFS は実用的な既定値です。素材に合わせて -30～0 dBFS の範囲で変更できます。複数選択時は合成後の推定平均が目標へ近づくよう配分し、ピーク超過は出力時にリミッターで抑制します。"
            wrapMode: Text.WordWrap
            font.pixelSize: 10
            opacity: 0.65
        }
    }

    Dialog {
        id: analysisScopeDialog

        property double targetDb: -8.0
        anchors.centerIn: parent
        width: 470
        modal: true
        title: "自動調整するトラック"
        closePolicy: Popup.NoAutoClose

        contentItem: Label {
            width: 430
            wrapMode: Text.WordWrap
            text: "すべての音声トラックを解析しますか？\n\n"
                  + "「全トラック」を選ぶと、すべてにチェックを入れて解析します。"
                  + "「チェック済みのみ」では現在の出力対象だけを解析します。"
        }

        footer: DialogButtonBox {
            Button {
                text: "キャンセル"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: analysisScopeDialog.close()
            }

            Button {
                text: "チェック済みのみ"
                enabled: mixerWindow.selectedAudioCount() > 0
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                onClicked: {
                    analysisScopeDialog.close()
                    backend.autoAdjustAudioTracks(analysisScopeDialog.targetDb, false)
                }
            }

            Button {
                text: "全トラック"
                highlighted: true
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: {
                    analysisScopeDialog.close()
                    backend.autoAdjustAudioTracks(analysisScopeDialog.targetDb, true)
                }
            }
        }
    }
}
