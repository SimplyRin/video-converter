// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QNetworkAccessManager>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QUrl>

class AppController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString selectedFileName READ selectedFileName NOTIFY selectedFileChanged)
    Q_PROPERTY(QUrl selectedFileUrl READ selectedFileUrl NOTIFY selectedFileChanged)
    Q_PROPERTY(bool hasSelectedFile READ hasSelectedFile NOTIFY selectedFileChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(bool toolsReady READ toolsReady NOTIFY toolsChanged)
    Q_PROPERTY(QString toolStatus READ toolStatus NOTIFY toolsChanged)
    Q_PROPERTY(bool checkingForUpdates READ checkingForUpdates NOTIFY updateStateChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY updateStateChanged)
    Q_PROPERTY(QString currentVersion READ currentVersion NOTIFY updateStateChanged)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY updateStateChanged)
    Q_PROPERTY(QUrl latestReleaseUrl READ latestReleaseUrl NOTIFY updateStateChanged)
    Q_PROPERTY(QString updateStatus READ updateStatus NOTIFY updateStateChanged)
    Q_PROPERTY(QString licenseText READ licenseText CONSTANT)
    Q_PROPERTY(QString thirdPartyNoticesText READ thirdPartyNoticesText CONSTANT)

public:
    explicit AppController(QObject *parent = nullptr);

    [[nodiscard]] QString selectedFileName() const;
    [[nodiscard]] QUrl selectedFileUrl() const;
    [[nodiscard]] bool hasSelectedFile() const;
    [[nodiscard]] bool busy() const;
    [[nodiscard]] double progress() const;
    [[nodiscard]] QString statusText() const;
    [[nodiscard]] bool toolsReady() const;
    [[nodiscard]] QString toolStatus() const;
    [[nodiscard]] bool checkingForUpdates() const;
    [[nodiscard]] bool updateAvailable() const;
    [[nodiscard]] QString currentVersion() const;
    [[nodiscard]] QString latestVersion() const;
    [[nodiscard]] QUrl latestReleaseUrl() const;
    [[nodiscard]] QString updateStatus() const;
    [[nodiscard]] QString licenseText() const;
    [[nodiscard]] QString thirdPartyNoticesText() const;

    Q_INVOKABLE void selectFile(const QUrl &url);
    Q_INVOKABLE void chooseFile();
    Q_INVOKABLE void clearSelectedFile();
    Q_INVOKABLE void refreshTools();
    Q_INVOKABLE void encode(int targetSizeMiB,
                            qint64 startMs = -1,
                            qint64 endMs = -1,
                            bool preferHardwareEncoder = false,
                            bool deleteCacheAfterEncoding = false);
    Q_INVOKABLE void cancelEncoding();
    Q_INVOKABLE void revealLatestOutput();
    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void openLatestRelease();
    Q_INVOKABLE void openProjectRepository();

signals:
    void selectedFileChanged();
    void busyChanged();
    void progressChanged();
    void statusTextChanged();
    void toolsChanged();
    void updateStateChanged();
    void errorOccurred(const QString &title, const QString &message);
    void encodingFinished(const QString &outputPath);

private:
    void locateTools();
    [[nodiscard]] QString locateTool(const QString &baseName) const;
    void probeDuration(int targetSizeMiB,
                       qint64 startMs,
                       qint64 endMs,
                       bool preferHardwareEncoder);
    void startEncoding(int targetSizeMiB,
                       qint64 startMs,
                       qint64 endMs,
                       qint64 durationMs,
                       bool preferHardwareEncoder);
    void startCacheCreation(qint64 startMs, qint64 endMs);
    void prepareEncodingAttempts(int videoBitrateKbps);
    void startCurrentEncodingAttempt();
    [[nodiscard]] QStringList availableHardwareEncoders() const;
    void consumeCacheProgressOutput();
    void consumeProgressOutput();
    void removeCacheFile();
    void setBusy(bool value);
    void setProgress(double value);
    void setStatusText(const QString &value);
    void fail(const QString &title, const QString &message);
    [[nodiscard]] QString buildOutputPath(int targetSizeMiB, qint64 startMs, qint64 endMs) const;
    [[nodiscard]] static QString formatTime(qint64 milliseconds);

    QString m_selectedFilePath;
    QString m_ffmpegPath;
    QString m_ffprobePath;
    QString m_latestOutputPath;
    QString m_cacheFilePath;
    QString m_encodingInputPath;
    bool m_busy = false;
    double m_progress = 0.0;
    QString m_statusText = QStringLiteral("エンコード！");
    qint64 m_activeDurationMs = 0;
    int m_pendingVideoBitrateKbps = 0;
    QByteArray m_cacheProgressBuffer;
    QByteArray m_cacheErrorBuffer;
    QByteArray m_progressBuffer;
    QList<QStringList> m_encodingAttempts;
    QStringList m_encodingAttemptLabels;
    qsizetype m_currentEncodingAttempt = 0;
    qsizetype m_hardwareEncodingAttemptCount = 0;
    bool m_hardwareEncodingRequested = false;
    bool m_deleteCacheAfterEncoding = false;
    QString m_activeEncoderLabel;
    QProcess m_probeProcess;
    QProcess m_cacheProcess;
    QProcess m_encodeProcess;
    QNetworkAccessManager m_networkManager;
    bool m_checkingForUpdates = false;
    bool m_updateAvailable = false;
    QString m_latestVersion;
    QUrl m_latestReleaseUrl;
    QString m_updateStatus = QStringLiteral("アップデートはまだ確認されていません。");
};
