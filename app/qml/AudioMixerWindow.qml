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

    onPreviewPlayingChanged: {
        if (!previewPlaying)
            meteringGracePeriod.elapsed = false
    }

    function openMixer() {
        show()
        raise()
        requestActivate()
    }

    function isTrackPreviewed(trackIndex, selected) {
        return backend.monitoredAudioTrack >= 0
               ? backend.monitoredAudioTrack === trackIndex : selected
    }

    // One waveform strip per source. trackIndex -1 renders the monitored mix.
    // Sample history is owned by the backend, so a strip keeps its picture even
    // when mediaTracksChanged() recreates the delegate it lives in.
    component WaveformStrip: Rectangle {
        id: strip

        property int trackIndex: -1
        property bool active: false
        property string caption: ""
        property color accentColor: "#ec64a5"
        property real currentLevelDb: -60

        function samples() {
            return strip.trackIndex < 0
                   ? backend.audioMixWaveform()
                   : backend.audioTrackWaveform(strip.trackIndex)
        }

        function readLevelDb() {
            return strip.trackIndex < 0
                   ? backend.audioMixLevelDb()
                   : backend.audioTrackLevelDb(strip.trackIndex)
        }

        color: "#17131b"
        radius: 3
        clip: true
        border.color: strip.active ? strip.accentColor : "#3b3641"

        onActiveChanged: {
            if (!active)
                currentLevelDb = -60
            waveCanvas.requestPaint()
        }

        Connections {
            target: backend
            function onAudioWaveformSampled() {
                strip.currentLevelDb = strip.active ? strip.readLevelDb() : -60
                waveCanvas.requestPaint()
            }
        }

        Label {
            id: captionLabel
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 5
            z: 2
            visible: strip.caption.length > 0
            text: strip.caption
            color: "white"
            font.pixelSize: 11
            opacity: strip.active ? 1 : 0.55
        }

        Label {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 5
            anchors.rightMargin: 8
            z: 2
            text: strip.active
                  ? Number(strip.currentLevelDb).toFixed(1) + " dBFS"
                  : "-- dBFS"
            color: "white"
            font.family: "monospace"
            font.pixelSize: 11
            opacity: strip.active ? 1 : 0.55
        }

        Canvas {
            id: waveCanvas
            anchors.fill: parent
            anchors.topMargin: captionLabel.visible ? 20 : 4
            anchors.bottomMargin: 4
            anchors.leftMargin: 4
            anchors.rightMargin: 4

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

                const values = strip.samples()
                if (values.length < 2)
                    return

                function offsetAt(index) {
                    const normalized = Math.max(0, Math.min(1,
                                                (Number(values[index]) + 60) / 60))
                    return normalized * (center - 1)
                }

                const step = width / (values.length - 1)
                context.beginPath()
                context.moveTo(0, center - offsetAt(0))
                for (let index = 1; index < values.length; ++index)
                    context.lineTo(index * step, center - offsetAt(index))
                for (let index = values.length - 1; index >= 0; --index)
                    context.lineTo(index * step, center + offsetAt(index))
                context.closePath()

                context.fillStyle = Qt.rgba(strip.accentColor.r, strip.accentColor.g,
                                            strip.accentColor.b,
                                            strip.active ? 0.28 : 0.12)
                context.fill()
                context.strokeStyle = strip.active ? "#ffffff" : "#7d7486"
                context.lineWidth = 1.5
                context.stroke()
            }
        }
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
                         && backend.audioTrackModel.count > 0
                onClicked: backend.setAllAudioTracksSelected(true)
            }

            Button {
                text: "すべて解除"
                enabled: !backend.busy && !backend.analyzingAudio
                         && backend.audioTrackModel.count > 0
                onClicked: backend.setAllAudioTracksSelected(false)
            }

            Button {
                text: "ミックスをモニター"
                visible: backend.monitoredAudioTrack >= 0
                onClicked: backend.setMonitoredAudioTrack(-1)
            }
        }

        WaveformStrip {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            trackIndex: -1
            active: mixerWindow.previewPlaying
            accentColor: "#ec64a5"
            caption: backend.monitoredAudioTrack >= 0
                     ? "音声トラック " + backend.monitoredAudioTrack + " をモニター中"
                     : "選択トラックのミックス (" + backend.audioTrackModel.selectedCount + " トラック)"
        }

        Label {
            Layout.fillWidth: true
            visible: mixerWindow.previewPlaying && !backend.audioMeteringAvailable
                     && meteringGracePeriod.elapsed
            text: "このQtメディアバックエンドは音声バッファを提供しないため、波形とレベル表示は動作しません"
                  + "（FFmpegバックエンドが必要です）。スピーカーへのモニター出力は影響を受けません。"
            wrapMode: Text.WordWrap
            font.pixelSize: 11
            color: "#ffb300"
        }

        Timer {
            id: meteringGracePeriod
            interval: 2500
            // Give playback a moment to start before blaming the backend.
            property bool elapsed: false
            running: mixerWindow.previewPlaying && !backend.audioMeteringAvailable
                     && !elapsed
            onTriggered: elapsed = true
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
                model: backend.audioTrackModel

                delegate: Rectangle {
                    id: trackRow
                    required property int index
                    required property int trackIndex
                    required property string label
                    required property bool selected
                    required property double gainDb
                    required property bool hasMeasurement
                    required property double meanVolumeDb
                    required property bool hasRecommendation
                    required property double recommendedGainDb
                    property bool previewed: mixerWindow.isTrackPreviewed(trackIndex,
                                                                          selected)
                    width: trackList.width
                    height: 132
                    color: index % 2 === 0 ? mixerWindow.palette.alternateBase
                                           : mixerWindow.palette.base

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            CheckBox {
                                id: enabledCheck
                                enabled: !backend.busy && !backend.analyzingAudio
                                onToggled: backend.setAudioTrackSelected(
                                               trackRow.trackIndex, checked)
                                Accessible.name: trackRow.label + " を出力に含める"
                                // A user click writes `checked` directly, which
                                // would break a plain binding now that delegates
                                // survive model updates. Binding keeps it synced.
                                Binding on checked {
                                    value: trackRow.selected
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 240
                                Layout.maximumWidth: 240
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: trackRow.label
                                    elide: Text.ElideRight
                                    font.bold: true
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: trackRow.hasMeasurement
                                          ? "測定平均: "
                                            + Number(trackRow.meanVolumeDb).toFixed(1)
                                            + " dBFS / 補正後: "
                                            + Number(trackRow.meanVolumeDb
                                                     + gainSlider.value).toFixed(1) + " dBFS"
                                          : "平均音量: 未測定"
                                    font.pixelSize: 11
                                    opacity: 0.75
                                }

                                Label {
                                    Layout.fillWidth: true
                                    visible: trackRow.hasRecommendation
                                    text: "おすすめゲイン: "
                                          + (trackRow.recommendedGainDb >= 0 ? "+" : "")
                                          + Number(trackRow.recommendedGainDb).toFixed(1)
                                          + " dB"
                                    color: mixerWindow.palette.highlight
                                    font.pixelSize: 11
                                    font.bold: true
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
                                enabled: trackRow.selected && !backend.busy
                                         && !backend.analyzingAudio
                                onMoved: {
                                    if (!pressed)
                                        backend.setAudioTrackGainDb(trackRow.trackIndex, value)
                                }
                                onPressedChanged: {
                                    if (!pressed)
                                        backend.setAudioTrackGainDb(trackRow.trackIndex, value)
                                }
                                Accessible.name: trackRow.label + " のゲイン"
                                // Dragging writes `value` directly, which would
                                // break a plain binding now that delegates
                                // survive model updates. Binding keeps it synced
                                // with the backend gain (e.g. after 自動調整).
                                Binding on value {
                                    value: trackRow.gainDb
                                }
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
                                text: trackRow.hasRecommendation ? "おすすめ" : "0 dB"
                                enabled: !backend.busy && !backend.analyzingAudio
                                onClicked: backend.setAudioTrackGainDb(
                                               trackRow.trackIndex,
                                               trackRow.hasRecommendation
                                               ? trackRow.recommendedGainDb : 0)
                            }

                            Button {
                                Layout.preferredWidth: 76
                                // Not `checkable`: clicking a checkable Button
                                // overwrites `checked` and breaks the binding to
                                // backend.monitoredAudioTrack, leaving stale
                                // "モニター中" labels on other rows.
                                readonly property bool monitoring:
                                    backend.monitoredAudioTrack === trackRow.trackIndex
                                text: monitoring ? "モニター中" : "モニター"
                                highlighted: monitoring
                                enabled: trackRow.selected && !backend.busy
                                onClicked: backend.setMonitoredAudioTrack(
                                               monitoring ? -1 : trackRow.trackIndex)

                                ToolTip.visible: hovered
                                ToolTip.text: trackRow.selected
                                              ? "選択中のこのトラックだけをプレビューします。"
                                              : "先にこのトラックを出力対象としてチェックしてください。"
                            }
                        }

                        WaveformStrip {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            trackIndex: trackRow.trackIndex
                            active: mixerWindow.previewPlaying && trackRow.previewed
                            accentColor: backend.monitoredAudioTrack === trackRow.trackIndex
                                         ? "#ec64a5" : "#43a047"
                            caption: trackRow.previewed
                                     ? "" : (trackRow.selected ? "モニター対象外" : "未選択")
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
                         && backend.audioTrackModel.count > 0
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
                enabled: backend.audioTrackModel.selectedCount > 0
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
