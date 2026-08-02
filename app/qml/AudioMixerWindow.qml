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

    // Playback position and trim range, in milliseconds, mirrored from the trim
    // window. The waveforms themselves are decoded from the file and cover the
    // whole track, so these only decide where the markers sit.
    property real mediaPosition: 0
    property real mediaDuration: 0
    property real trimStart: -1
    property real trimEnd: -1

    readonly property real positionRatio: mediaDuration > 0
        ? Math.max(0, Math.min(1, mediaPosition / mediaDuration)) : 0
    readonly property real trimStartRatio: mediaDuration > 0 && trimStart >= 0
        ? Math.max(0, Math.min(1, trimStart / mediaDuration)) : 0
    readonly property real trimEndRatio: mediaDuration > 0 && trimEnd >= 0
        ? Math.max(0, Math.min(1, trimEnd / mediaDuration)) : 1

    // Visible slice of the timeline, as fractions of the media duration. Every
    // strip shares it so the tracks stay lined up while zooming and panning.
    property real viewStart: 0
    property real viewEnd: 1
    readonly property real viewSpan: Math.max(minimumViewSpan, viewEnd - viewStart)
    readonly property bool zoomed: viewSpan < 1
    // Do not zoom past roughly a second across the strip; beyond that the
    // stored 2 ms buckets would just be stretched.
    readonly property real minimumViewSpan: mediaDuration > 0
        ? Math.min(1, 1000 / mediaDuration) : 1

    function setView(start, span) {
        const clampedSpan = Math.max(minimumViewSpan, Math.min(1, span))
        const clampedStart = Math.max(0, Math.min(1 - clampedSpan, start))
        viewStart = clampedStart
        viewEnd = clampedStart + clampedSpan
    }

    // Keeps the timeline point under `anchorRatio` where it is, so zooming with
    // the wheel homes in on whatever the pointer is over.
    function zoomBy(factor, anchorRatio) {
        const span = viewSpan / factor
        const anchor = Math.max(viewStart, Math.min(viewEnd, anchorRatio))
        const offset = viewSpan > 0 ? (anchor - viewStart) / viewSpan : 0.5
        setView(anchor - offset * span, span)
    }

    function zoomToFit() { setView(0, 1) }

    function panBy(deltaRatio) { setView(viewStart + deltaRatio, viewSpan) }

    // Follows the playhead while it runs off the visible slice.
    function revealPosition() {
        if (!zoomed || mediaDuration <= 0)
            return
        if (positionRatio < viewStart || positionRatio > viewEnd)
            setView(positionRatio - viewSpan / 2, viewSpan)
    }

    onMediaDurationChanged: zoomToFit()
    onPositionRatioChanged: revealPosition()

    function formatTime(milliseconds) {
        if (!Number.isFinite(milliseconds) || milliseconds < 0)
            milliseconds = 0
        const totalSeconds = Math.floor(milliseconds / 1000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + String(seconds).padStart(2, "0")
    }

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
        property bool showTimeAxis: false
        // The waveform comes from the file, so it stays fully drawn whether or
        // not playback is running. `active` now only governs the live readout.
        property bool emphasized: true
        property bool hasWaveform: false
        readonly property bool waveformPending: !hasWaveform
                                                && backend.audioWaveformsAnalyzing

        // One value per pixel of the visible slice, so the payload stays the
        // same size no matter how far the view is zoomed in.
        function samples() {
            return backend.audioWaveformRange(strip.trackIndex,
                                              mixerWindow.viewStart,
                                              mixerWindow.viewEnd,
                                              Math.max(2, Math.round(waveCanvas.width)))
        }

        // Maps a timeline fraction onto an x inside the canvas.
        function xAt(ratio) {
            return waveCanvas.width * (ratio - mixerWindow.viewStart) / mixerWindow.viewSpan
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
        }

        onEmphasizedChanged: waveCanvas.requestPaint()

        Component.onCompleted: strip.hasWaveform = strip.samples().length >= 2

        // The picture only changes when a track finishes decoding or the mix is
        // recomputed; the playhead is a separate overlay so seeking never has
        // to repaint the canvas.
        // Zooming and panning change which slice is drawn, so the canvas has to
        // be repainted; the playhead and the trim shading are plain overlays.
        Connections {
            target: mixerWindow
            function onViewStartChanged() { waveCanvas.requestPaint() }
            function onViewEndChanged() { waveCanvas.requestPaint() }
        }

        Connections {
            target: backend
            function onAudioWaveformsChanged() {
                strip.hasWaveform = strip.samples().length >= 2
                waveCanvas.requestPaint()
            }
            function onAudioTrackLevelsChanged() {
                strip.currentLevelDb = strip.active ? strip.readLevelDb() : -60
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
                                            strip.emphasized ? 0.28 : 0.12)
                context.fill()
                context.strokeStyle = strip.emphasized ? "#ffffff" : "#7d7486"
                context.lineWidth = 1.5
                context.stroke()
            }
        }

        // Everything outside the trim range is dimmed, so the picture shows at
        // a glance which audio actually reaches the output. Both bands are
        // clipped to the canvas, which keeps them right while zoomed.
        Item {
            anchors.fill: waveCanvas
            clip: true
            z: 1

            Rectangle {
                x: -waveCanvas.width
                width: waveCanvas.width + strip.xAt(mixerWindow.trimStartRatio)
                height: parent.height
                visible: mixerWindow.trimStartRatio > 0
                color: "#0d0a10"
                opacity: 0.6
            }

            Rectangle {
                x: strip.xAt(mixerWindow.trimEndRatio)
                width: waveCanvas.width * 2
                height: parent.height
                visible: mixerWindow.trimEndRatio < 1
                color: "#0d0a10"
                opacity: 0.6
            }
        }

        Rectangle {
            id: playhead
            visible: mixerWindow.mediaDuration > 0
                     && mixerWindow.positionRatio >= mixerWindow.viewStart
                     && mixerWindow.positionRatio <= mixerWindow.viewEnd
            x: waveCanvas.x + strip.xAt(mixerWindow.positionRatio)
            y: waveCanvas.y
            width: 1
            height: waveCanvas.height
            color: strip.active ? "#ffffff" : "#9d94a6"
            z: 3
        }

        Label {
            anchors.left: waveCanvas.left
            anchors.bottom: waveCanvas.bottom
            z: 2
            visible: strip.showTimeAxis && mixerWindow.mediaDuration > 0
            text: mixerWindow.formatTime(mixerWindow.viewStart * mixerWindow.mediaDuration)
            color: "#9d94a6"
            font.family: "monospace"
            font.pixelSize: 10
        }

        Label {
            anchors.right: waveCanvas.right
            anchors.bottom: waveCanvas.bottom
            z: 2
            visible: strip.showTimeAxis && mixerWindow.mediaDuration > 0
            text: mixerWindow.formatTime(mixerWindow.viewEnd * mixerWindow.mediaDuration)
            color: "#9d94a6"
            font.family: "monospace"
            font.pixelSize: 10
        }

        // Wheel zooms around the pointer, drag pans, like a waveform editor.
        MouseArea {
            anchors.fill: waveCanvas
            z: 4
            acceptedButtons: Qt.LeftButton
            cursorShape: mixerWindow.zoomed ? Qt.OpenHandCursor : Qt.ArrowCursor
            property real pressRatio: 0

            onWheel: function(wheel) {
                const ratio = mixerWindow.viewStart
                            + (wheel.x / width) * mixerWindow.viewSpan
                mixerWindow.zoomBy(wheel.angleDelta.y > 0 ? 1.25 : 1 / 1.25, ratio)
                wheel.accepted = true
            }

            onPressed: function(mouse) {
                pressRatio = mixerWindow.viewStart + (mouse.x / width) * mixerWindow.viewSpan
            }

            onPositionChanged: function(mouse) {
                if (!pressed || !mixerWindow.zoomed)
                    return
                const ratio = mixerWindow.viewStart + (mouse.x / width) * mixerWindow.viewSpan
                mixerWindow.panBy(pressRatio - ratio)
            }
        }

        Label {
            anchors.centerIn: waveCanvas
            z: 2
            visible: strip.waveformPending
            text: "波形を解析中…"
            color: "#9d94a6"
            font.pixelSize: 11
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

        // Zoom applies to every strip at once, so the tracks stay aligned.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            enabled: mixerWindow.mediaDuration > 0

            Label {
                text: "表示範囲:"
                font.pixelSize: 12
            }

            Button {
                text: "－"
                implicitWidth: 32
                enabled: mixerWindow.zoomed
                ToolTip.visible: hovered
                ToolTip.text: "縮小"
                onClicked: mixerWindow.zoomBy(1 / 1.6, mixerWindow.positionRatio)
            }

            Button {
                text: "＋"
                implicitWidth: 32
                enabled: mixerWindow.viewSpan > mixerWindow.minimumViewSpan
                ToolTip.visible: hovered
                ToolTip.text: "拡大"
                onClicked: mixerWindow.zoomBy(1.6, mixerWindow.positionRatio)
            }

            Button {
                text: "全体"
                enabled: mixerWindow.zoomed
                onClicked: mixerWindow.zoomToFit()
            }

            ScrollBar {
                id: viewScrollBar
                Layout.fillWidth: true
                orientation: Qt.Horizontal
                policy: ScrollBar.AlwaysOn
                visible: mixerWindow.zoomed
                size: mixerWindow.viewSpan
                position: mixerWindow.viewStart
                // Only a drag on the bar itself may move the view; otherwise
                // this would fight the binding while zooming or following.
                onPositionChanged: {
                    if (pressed)
                        mixerWindow.setView(position, mixerWindow.viewSpan)
                }
            }

            Label {
                text: mixerWindow.zoomed
                      ? Math.round(1 / mixerWindow.viewSpan) + "倍"
                      : "全体"
                font.pixelSize: 11
                color: "#9d94a6"
            }
        }

        WaveformStrip {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            trackIndex: -1
            active: mixerWindow.previewPlaying
            emphasized: true
            showTimeAxis: true
            accentColor: "#ec64a5"
            caption: backend.monitoredAudioTrack >= 0
                     ? "音声トラック " + backend.monitoredAudioTrack + " をモニター中"
                     : "選択トラックのミックス (" + backend.audioTrackModel.selectedCount + " トラック)"
        }

        Label {
            Layout.fillWidth: true
            visible: mixerWindow.previewPlaying && !backend.audioMeteringAvailable
                     && meteringGracePeriod.elapsed
            text: "このQtメディアバックエンドは音声バッファを提供しないため、リアルタイムのレベル表示は動作しません"
                  + "（FFmpegバックエンドが必要です）。波形はファイルから解析するため影響を受けず、"
                  + "スピーカーへのモニター出力も影響を受けません。"
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
                            emphasized: trackRow.previewed
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
