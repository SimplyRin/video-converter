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
    property url previewSource: ""

    function synchronizeAudioPreviews(forcePosition) {
        for (let index = 0; index < audioPreviewPlayers.count; ++index) {
            const preview = audioPreviewPlayers.objectAt(index)
            if (preview)
                preview.synchronize(forcePosition)
        }
    }

    function openVideo(url, targetSize) {
        targetSizeMiB = targetSize
        startPosition = -1
        endPosition = -1
        validationText.text = ""
        backend.resetAudioTrackLevels()
        previewSource = url
        show()
        raise()
        requestActivate()
        player.play()
    }

    onClosing: function(close) {
        audioMixerWindow.close()
        player.stop()
        synchronizeAudioPreviews(true)
        previewSource = ""
        backend.resetAudioTrackLevels()
    }

    // Follow the system default output device. The preview players now live
    // for as long as the track model, so without this an AudioOutput would
    // stay attached to whatever device was the default when it was created.
    MediaDevices {
        id: mediaDevices
    }

    AudioOutput {
        id: silentVideoAudioOutput
        muted: true
        volume: 0
    }

    MediaPlayer {
        id: player
        source: trimWindow.previewSource
        audioOutput: silentVideoAudioOutput
        videoOutput: videoOutput
        activeVideoTrack: backend.selectedVideoTrack
        activeAudioTrack: -1

        onPlaybackStateChanged: Qt.callLater(function() {
            trimWindow.synchronizeAudioPreviews(true)
            if (playbackState !== MediaPlayer.PlayingState)
                backend.resetAudioTrackLevels()
        })

        onErrorOccurred: function(error, errorString) {
            validationText.text = "動画を再生できません: " + errorString
        }
    }

    Instantiator {
        id: audioPreviewPlayers
        model: backend.audioTrackModel

        delegate: Item {
            id: audioPreview

            required property int trackIndex
            required property bool selected
            required property double gainDb
            property bool previewEnabled: selected
                                          && (backend.monitoredAudioTrack < 0
                                              || backend.monitoredAudioTrack
                                                 === trackIndex)
            visible: false

            function applyConfiguredTrack() {
                const configuredTrack = audioPreview.trackIndex
                if (!previewEnabled
                    || configuredTrack < 0
                    || trackPlayer.audioTracks.length <= configuredTrack) {
                    return false
                }
                if (trackPlayer.activeAudioTrack !== configuredTrack) {
                    trackPlayer.activeAudioTrack = configuredTrack
                    levelMeter.reset()
                    backend.setAudioTrackLevelDb(configuredTrack, -60)
                }
                return trackPlayer.activeAudioTrack === configuredTrack
            }

            function synchronize(forcePosition) {
                if (!previewEnabled || trimWindow.previewSource.toString().length === 0) {
                    trackPlayer.stop()
                    levelMeter.reset()
                    backend.setAudioTrackLevelDb(audioPreview.trackIndex, -60)
                    return
                }

                const ready = trackPlayer.mediaStatus === MediaPlayer.LoadedMedia
                           || trackPlayer.mediaStatus === MediaPlayer.BufferingMedia
                           || trackPlayer.mediaStatus === MediaPlayer.BufferedMedia
                           || trackPlayer.mediaStatus === MediaPlayer.StalledMedia
                if (!ready)
                    return

                // Some Qt multimedia backends restore audio track 0 while a
                // new source is loading. Never start audio until our explicit
                // track selection has been accepted by the backend.
                if (!applyConfiguredTrack())
                    return

                if (forcePosition || Math.abs(trackPlayer.position - player.position) > 120)
                    trackPlayer.position = player.position

                if (player.playbackState === MediaPlayer.PlayingState) {
                    if (trackPlayer.playbackState !== MediaPlayer.PlayingState)
                        trackPlayer.play()
                } else if (player.playbackState === MediaPlayer.PausedState) {
                    if (trackPlayer.playbackState !== MediaPlayer.PausedState)
                        trackPlayer.pause()
                } else {
                    trackPlayer.stop()
                    levelMeter.reset()
                }
            }

            onSelectedChanged: Qt.callLater(function() {
                audioPreview.synchronize(true)
            })
            onPreviewEnabledChanged: Qt.callLater(function() {
                audioPreview.synchronize(true)
            })

            AudioOutput {
                id: trackAudioOutput
                device: mediaDevices.defaultAudioOutput
                muted: !audioPreview.previewEnabled
                       || trackPlayer.activeAudioTrack
                          !== audioPreview.trackIndex
                volume: Math.max(0, Math.min(1,
                            0.05 * Math.pow(10, audioPreview.gainDb / 20)))
            }

            AudioLevelMeter {
                id: levelMeter
                gainDb: audioPreview.gainDb
                onLevelDbChanged: backend.setAudioTrackLevelDb(
                                      audioPreview.trackIndex, levelDb)
                // Tell the backend once any media backend actually delivers
                // audio buffers, so the mixer can explain a flat waveform.
                onReceivingBuffersChanged: {
                    if (receivingBuffers)
                        backend.reportAudioMeteringAvailable()
                }
            }

            MediaPlayer {
                id: trackPlayer
                source: audioPreview.previewEnabled ? trimWindow.previewSource : ""
                audioOutput: trackAudioOutput
                audioBufferOutput: levelMeter
                activeVideoTrack: -1
                // Keep the default track active while the source is loading.
                // Once audioTracks is populated, applyConfiguredTrack()
                // switches to this player's assigned track before playback.
                activeAudioTrack: 0

                onAudioTracksChanged: Qt.callLater(function() {
                    audioPreview.applyConfiguredTrack()
                    audioPreview.synchronize(true)
                })

                onActiveAudioTrackChanged: {
                    if (activeAudioTrack !== audioPreview.trackIndex) {
                        levelMeter.reset()
                    }
                    Qt.callLater(function() {
                        audioPreview.applyConfiguredTrack()
                        audioPreview.synchronize(true)
                    })
                }

                onMediaStatusChanged: Qt.callLater(function() {
                    audioPreview.applyConfiguredTrack()
                    audioPreview.synchronize(true)
                })
            }

            Component.onDestruction: {
                levelMeter.reset()
                backend.setAudioTrackLevelDb(audioPreview.trackIndex, -60)
            }
        }
    }

    Timer {
        interval: 400
        repeat: true
        running: trimWindow.visible
                 && player.playbackState === MediaPlayer.PlayingState
        onTriggered: trimWindow.synchronizeAudioPreviews(false)
    }

    // The waveform history lives in the backend so it survives delegate
    // teardown when a new file resets the audio track model.
    Binding {
        target: backend
        property: "audioWaveformCapturing"
        value: trimWindow.visible
               && player.playbackState === MediaPlayer.PlayingState
        restoreMode: Binding.RestoreNone
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
            spacing: 6

            Button {
                text: player.playbackState === MediaPlayer.PlayingState ? "一時停止" : "再生"
                onClicked: {
                    if (player.playbackState === MediaPlayer.PlayingState)
                        player.pause()
                    else
                        player.play()
                }
            }

            Button {
                id: videoTrackButton
                visible: backend.videoTracks.length > 1
                enabled: !backend.busy && !backend.tracksLoading
                text: "ビデオトラック ▾"
                onClicked: videoTrackMenu.popup()

                Menu {
                    id: videoTrackMenu

                    Instantiator {
                        model: backend.videoTracks
                        delegate: MenuItem {
                            required property var modelData
                            text: modelData.label
                            checkable: true
                            checked: modelData.selected
                            onTriggered: backend.setSelectedVideoTrack(modelData.index)
                        }
                        onObjectAdded: function(index, object) {
                            videoTrackMenu.insertItem(index, object)
                        }
                        onObjectRemoved: function(index, object) {
                            videoTrackMenu.removeItem(object)
                        }
                    }
                }
            }

            Button {
                id: audioTrackButton
                visible: backend.audioTrackModel.count > 0
                enabled: !backend.busy && !backend.tracksLoading && !backend.analyzingAudio
                text: "音声トラック (" + backend.audioTrackModel.selectedCount
                      + "/" + backend.audioTrackModel.count + ") ▾"
                onClicked: audioTrackMenu.popup()

                ToolTip.visible: hovered
                ToolTip.text: "選択した音声はプレビューと出力の両方ですべて合成します。"

                Menu {
                    id: audioTrackMenu

                    Instantiator {
                        model: backend.audioTrackModel
                        delegate: MenuItem {
                            id: audioTrackMenuItem
                            required property int trackIndex
                            required property bool selected
                            required property string label
                            text: label
                            checkable: true
                            onTriggered: backend.setAudioTrackSelected(trackIndex, !selected)
                            // A user click writes `checked` directly, which
                            // would break a plain binding now that delegates
                            // survive model updates. Binding keeps it synced.
                            Binding on checked {
                                value: audioTrackMenuItem.selected
                            }
                        }
                        onObjectAdded: function(index, object) {
                            audioTrackMenu.insertItem(index, object)
                        }
                        onObjectRemoved: function(index, object) {
                            audioTrackMenu.removeItem(object)
                        }
                    }

                    MenuSeparator { }

                    MenuItem {
                        text: "音量ミキサーを開く…"
                        onTriggered: audioMixerWindow.openMixer()
                    }
                }
            }

            Button {
                visible: backend.audioTrackModel.count > 0
                enabled: !backend.busy
                text: "ミキサー"
                onClicked: audioMixerWindow.openMixer()
            }

            Label {
                visible: backend.tracksLoading
                text: "トラック解析中…"
                font.pixelSize: 11
                opacity: 0.7
            }

            Item { Layout.fillWidth: true }
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
            onMoved: {
                player.position = value
                trimWindow.synchronizeAudioPreviews(true)
            }
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
            ToolTip.text: "トリミング範囲を指定した場合に作成される一時 MKV が対象です。"
        }

        Label {
            Layout.fillWidth: true
            text: "一時ファイルは、指定したトリミング範囲と選択トラックを再エンコードせずに保存した無劣化 MKV です。元動画と同じフォルダーに保存されます。"
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
                enabled: !backend.tracksLoading && !backend.analyzingAudio
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

    AudioMixerWindow {
        id: audioMixerWindow
        previewPlaying: player.playbackState === MediaPlayer.PlayingState
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
