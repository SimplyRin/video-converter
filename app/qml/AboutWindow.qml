// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts

ApplicationWindow {
    id: window

    width: 560
    height: 600
    minimumWidth: 500
    minimumHeight: 520
    visible: false
    modality: Qt.ApplicationModal
    flags: Qt.Dialog
    title: backend.updateAvailable ? "DiscordVideo - アップデートがあります" : "DiscordVideo - アプリ情報"
    color: palette.window

    function showSection(index) {
        tabs.currentIndex = index
        show()
        // Only valid once the window exists, because the frame size that the
        // clamp has to account for is decided by the window manager.
        backend.keepWindowOnScreen(window)
        raise()
        requestActivate()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Image {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                source: "qrc:/icons/DiscordVideo.ico"
                fillMode: Image.PreserveAspectFit
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: "DiscordVideo"
                    font.pixelSize: 21
                    font.bold: true
                }

                Label {
                    text: "バージョン " + backend.currentVersion
                    color: window.palette.placeholderText
                }
            }

            Rectangle {
                visible: backend.updateAvailable
                Layout.preferredWidth: updateBadgeLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: 14
                color: window.palette.window.hslLightness < 0.5 ? "#6d4100" : "#fff3e0"
                border.color: window.palette.window.hslLightness < 0.5 ? "#ffb74d" : "#ef6c00"

                Label {
                    id: updateBadgeLabel
                    anchors.centerIn: parent
                    text: "更新あり"
                    font.bold: true
                    color: window.palette.window.hslLightness < 0.5 ? "#ffd180" : "#bf360c"
                }
            }
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true

            TabButton { text: "概要" }
            TabButton { text: "設定" }
            TabButton { text: backend.updateAvailable ? "アップデートあり" : "アップデート" }
            TabButton { text: "ライセンス" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            ScrollView {
                id: overviewScroll
                clip: true

                ColumnLayout {
                    width: overviewScroll.availableWidth
                    spacing: 14

                    Label {
                        Layout.fillWidth: true
                        text: "動画を指定したファイルサイズへ変換する、Windows / macOS 向けアプリケーションです。"
                        wrapMode: Text.WordWrap
                    }

                    GroupBox {
                        Layout.fillWidth: true
                        title: "オープンソースソフトウェア"

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                text: "Copyright © SimplyRin\nGNU General Public License v3.0 or later"
                                wrapMode: Text.WordWrap
                            }

                            Label {
                                Layout.fillWidth: true
                                text: "このソフトウェアは無保証で提供され、GNU GPL に従って再配布・変更できます。Qt 6、GPL 版 FFmpeg、x264 を使用しています。詳細は「ライセンス」タブで確認できます。"
                                wrapMode: Text.WordWrap
                                color: window.palette.placeholderText
                            }
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "GitHub でソースコードを見る"
                        onClicked: backend.openProjectRepository()
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            ScrollView {
                id: settingsScroll
                clip: true

                ColumnLayout {
                    width: settingsScroll.availableWidth
                    spacing: 14

                    GroupBox {
                        Layout.fillWidth: true
                        title: "エンコード"

                        GridLayout {
                            anchors.fill: parent
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 10

                            Label { text: "既定の目標ファイルサイズ:" }

                            RowLayout {
                                spacing: 6

                                SpinBox {
                                    id: defaultSizeSpin
                                    from: 1
                                    to: 4096
                                    editable: true
                                    enabled: !backend.busy
                                    value: backend.defaultTargetSizeMiB
                                    onValueModified: backend.setDefaultTargetSizeMiB(value)
                                }

                                Label { text: "MB" }
                            }

                            Label { text: "音声ビットレート:" }

                            RowLayout {
                                spacing: 6

                                ComboBox {
                                    id: audioBitrateBox
                                    Layout.preferredWidth: 110
                                    enabled: !backend.busy
                                    model: [32, 64, 96, 128, 160, 192, 256, 320]
                                    currentIndex: Math.max(0, model.indexOf(backend.audioBitrateKbps))
                                    onActivated: backend.setAudioBitrateKbps(model[currentIndex])
                                }

                                Label { text: "kbps" }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "目標ファイルサイズはメイン画面で毎回変更できます。ここで設定した値は、"
                              + "入力欄を空のままにしたときに使われます。"
                        font.pixelSize: 12
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "映像のビットレートは、目標ファイルサイズから音声ビットレートを差し引いた残りです。"
                              + "音声を上げるほど音質は良くなりますが、その分だけ映像のビットレートが下がります。"
                              + "既定の 96 kbps は容量を優先した値で、音質を重視する場合は 128 kbps 以上をおすすめします。"
                        font.pixelSize: 12
                        color: "#9d94a6"
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        visible: backend.audioBitrateKbps >= 192
                        text: "短い動画では、音声に大きな割合を割り当てると映像のビットレートが不足して"
                              + "変換できないことがあります。"
                        font.pixelSize: 12
                        color: "#ffb300"
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: updateColumn.implicitHeight + 28
                        radius: 8
                        color: backend.updateAvailable
                               ? (window.palette.window.hslLightness < 0.5 ? "#4b330f" : "#fff8e1")
                               : window.palette.alternateBase
                        border.width: 1
                        border.color: backend.updateAvailable
                                      ? (window.palette.window.hslLightness < 0.5 ? "#ffb74d" : "#f57c00")
                                      : window.palette.mid

                        ColumnLayout {
                            id: updateColumn
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6

                            Label {
                                Layout.fillWidth: true
                                text: backend.updateAvailable ? "新しいバージョンを利用できます" : "アップデート情報"
                                font.pixelSize: 16
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Label {
                                Layout.fillWidth: true
                                text: backend.updateStatus
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 18
                        rowSpacing: 8

                        Label { text: "現在のバージョン"; color: window.palette.placeholderText }
                        Label { text: "v" + backend.currentVersion; font.bold: true }
                        Label { text: "最新のリリース"; color: window.palette.placeholderText }
                        Label {
                            text: backend.latestVersion.length > 0 ? backend.latestVersion : "未確認"
                            font.bold: true
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: backend.latestVersion.length > 0
                              ? backend.latestVersion + " の GitHub Release を開く"
                              : "GitHub Release を開く"
                        highlighted: backend.updateAvailable
                        onClicked: backend.openLatestRelease()
                    }

                    CheckBox {
                        Layout.fillWidth: true
                        text: "プリリリース版を対象とする"
                        checked: backend.includePrereleaseUpdates
                        enabled: !backend.checkingForUpdates && !backend.prereleaseBuild
                        onToggled: backend.setIncludePrereleaseUpdates(checked)

                        ToolTip.visible: hovered
                        ToolTip.text: backend.prereleaseBuild
                                      ? "プリリリース版のアプリでは自動的に有効になります。"
                                      : "GitHub の Pre-release もアップデート候補として確認します。"
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: backend.prereleaseBuild
                        text: "このアプリはプリリリース版のため、プリリリース更新を自動的に確認します。"
                        wrapMode: Text.WordWrap
                        color: window.palette.placeholderText
                        font.pixelSize: 11
                    }

                    Button {
                        Layout.fillWidth: true
                        text: backend.checkingForUpdates ? "アップデートを確認中..." : "もう一度確認する"
                        enabled: !backend.checkingForUpdates
                        onClicked: backend.checkForUpdates()
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "起動時に GitHub Releases を確認します。更新がある場合は、メイン画面の「i」が点灯します。"
                        wrapMode: Text.WordWrap
                        color: window.palette.placeholderText
                        font.pixelSize: 11
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    Label {
                        Layout.fillWidth: true
                        text: "配布物に含まれるライセンスと第三者コンポーネントの情報を確認できます。"
                        wrapMode: Text.WordWrap
                    }

                    ComboBox {
                        id: licenseSelector
                        Layout.fillWidth: true
                        model: [
                            "オープンソースライセンス情報 (Qt / FFmpeg / x264)",
                            "GNU General Public License v3"
                        ]
                    }

                    ScrollView {
                        id: licenseScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextArea {
                            width: licenseScroll.availableWidth
                            text: licenseSelector.currentIndex === 0
                                  ? backend.thirdPartyNoticesText
                                  : backend.licenseText
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            font.family: Qt.platform.os === "windows" ? "Consolas" : "Menlo"
                            font.pixelSize: 11
                            color: window.palette.text
                            background: Rectangle {
                                color: window.palette.base
                                border.color: window.palette.mid
                                radius: 4
                            }
                        }
                    }
                }
            }
        }

        DialogButtonBox {
            Layout.fillWidth: true
            standardButtons: DialogButtonBox.Close
            onRejected: window.hide()
        }
    }
}
