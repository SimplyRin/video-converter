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
    title: backend.updateAvailable ? "DiscordVideo — アップデートがあります" : "DiscordVideo — アプリ情報"
    color: palette.window

    function showSection(index) {
        tabs.currentIndex = index
        show()
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
            TabButton { text: backend.updateAvailable ? "アップデート ●" : "アップデート" }
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
                        text: "動画を指定したファイルサイズへ変換する、Windows / macOS向けアプリケーションです。"
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
                                text: "このソフトウェアは無保証で提供され、GNU GPLに従って再配布・変更できます。Qt 6、GPL版FFmpeg、x264を使用しています。詳細は「ライセンス」タブで確認できます。"
                                wrapMode: Text.WordWrap
                                color: window.palette.placeholderText
                            }
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "GitHubでソースコードを見る"
                        onClicked: backend.openProjectRepository()
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
                              ? backend.latestVersion + " のGitHub Releaseを開く"
                              : "GitHub Releaseを開く"
                        highlighted: backend.updateAvailable
                        onClicked: backend.openLatestRelease()
                    }

                    Button {
                        Layout.fillWidth: true
                        text: backend.checkingForUpdates ? "アップデートを確認中..." : "もう一度確認する"
                        enabled: !backend.checkingForUpdates
                        onClicked: backend.checkForUpdates()
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "起動時にGitHub Releasesを非同期で確認します。更新がある場合は、メイン画面の「i」が点灯します。"
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
                            "オープンソースライセンス情報（Qt / FFmpeg / x264）",
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
