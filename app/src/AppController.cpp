// SPDX-License-Identifier: GPL-3.0-or-later

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <objbase.h>
#include <shlobj.h>
#endif

#include "AppController.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUuid>
#include <QtGlobal>

#include <algorithm>
#include <cmath>

namespace {
constexpr int audioBitrateKbps = 96;
constexpr int minimumVideoBitrateKbps = 50;
constexpr double containerSafetyFactor = 0.97;
}

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_probeProcess.setProcessChannelMode(QProcess::SeparateChannels);
    m_cacheProcess.setProcessChannelMode(QProcess::SeparateChannels);
    m_encodeProcess.setProcessChannelMode(QProcess::SeparateChannels);

    connect(&m_cacheProcess, &QProcess::readyReadStandardOutput,
            this, &AppController::consumeCacheProgressOutput);
    connect(&m_cacheProcess, &QProcess::readyReadStandardError, this, [this] {
        m_cacheErrorBuffer += m_cacheProcess.readAllStandardError();
        constexpr qsizetype maximumErrorBufferSize = 32 * 1024;
        if (m_cacheErrorBuffer.size() > maximumErrorBufferSize) {
            m_cacheErrorBuffer = m_cacheErrorBuffer.right(maximumErrorBufferSize);
        }
    });
    connect(&m_cacheProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
                if (!m_busy) {
                    return;
                }

                const bool succeeded = exitStatus == QProcess::NormalExit
                    && exitCode == 0
                    && QFileInfo(m_cacheFilePath).size() > 0;
                if (!succeeded) {
                    const QString errorMessage = QString::fromUtf8(m_cacheErrorBuffer).trimmed();
                    removeCacheFile();
                    setBusy(false);
                    setProgress(0.0);
                    fail(QStringLiteral("キャッシュ作成失敗"), errorMessage);
                    return;
                }

                setProgress(0.0);
                prepareEncodingAttempts(m_pendingVideoBitrateKbps);
            });

    connect(&m_encodeProcess, &QProcess::readyReadStandardOutput,
            this, &AppController::consumeProgressOutput);
    connect(&m_encodeProcess, &QProcess::readyReadStandardError, this, [this] {
        // Drain stderr continuously so FFmpeg can never block on a full pipe.
        m_encodeProcess.readAllStandardError();
    });
    connect(&m_encodeProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
                if (!m_busy) {
                    return;
                }

                const bool succeeded = exitStatus == QProcess::NormalExit && exitCode == 0;
                if (!succeeded) {
                    if (!m_latestOutputPath.isEmpty()) {
                        QFile::remove(m_latestOutputPath);
                    }

                    if (m_currentEncodingAttempt + 1 < m_encodingAttempts.size()) {
                        ++m_currentEncodingAttempt;
                        setProgress(0.0);
                        m_progressBuffer.clear();
                        startCurrentEncodingAttempt();
                        return;
                    }

                    setBusy(false);
                    setStatusText(QStringLiteral("エンコード！"));
                    emit errorOccurred(QStringLiteral("エンコード失敗"),
                                       QStringLiteral("FFmpeg が正常に終了しませんでした。"));
                    return;
                }

                setBusy(false);
                setProgress(1.0);
                setStatusText(QStringLiteral("完了"));
                if (m_deleteCacheAfterEncoding) {
                    removeCacheFile();
                }
                emit encodingFinished(m_latestOutputPath);
            });

    locateTools();
}

QString AppController::selectedFileName() const
{
    return m_selectedFilePath.isEmpty()
        ? QStringLiteral("選択されていません。")
        : QFileInfo(m_selectedFilePath).fileName();
}

QUrl AppController::selectedFileUrl() const
{
    return m_selectedFilePath.isEmpty() ? QUrl{} : QUrl::fromLocalFile(m_selectedFilePath);
}

bool AppController::hasSelectedFile() const
{
    return !m_selectedFilePath.isEmpty();
}

bool AppController::busy() const
{
    return m_busy;
}

double AppController::progress() const
{
    return m_progress;
}

QString AppController::statusText() const
{
    return m_statusText;
}

bool AppController::toolsReady() const
{
    return !m_ffmpegPath.isEmpty() && !m_ffprobePath.isEmpty();
}

QString AppController::toolStatus() const
{
    if (toolsReady()) {
        return QStringLiteral("FFmpeg を利用できます。");
    }
    return QStringLiteral("FFmpeg または FFprobe が見つかりません。app/tools/ffmpeg へ配置するか、PATH 設定してください。");
}

void AppController::selectFile(const QUrl &url)
{
    const QString localPath = url.toLocalFile();
    const QFileInfo info(localPath);
    if (!info.exists() || !info.isFile()) {
        fail(QStringLiteral("ファイル選択エラー"), QStringLiteral("動画ファイルを開けません。"));
        return;
    }

    m_selectedFilePath = info.absoluteFilePath();
    emit selectedFileChanged();
}

void AppController::chooseFile()
{
    if (m_busy) {
        return;
    }

    const QString path = QFileDialog::getOpenFileName(
        nullptr,
        QStringLiteral("動画ファイルを選択"),
        QString(),
        QStringLiteral("動画ファイル (*.mp4 *.mkv *.mov *.avi *.webm *.m4v);;すべてのファイル (*)"));
    if (!path.isEmpty()) {
        selectFile(QUrl::fromLocalFile(path));
    }
}

void AppController::clearSelectedFile()
{
    if (m_busy) {
        return;
    }
    m_selectedFilePath.clear();
    emit selectedFileChanged();
}

void AppController::refreshTools()
{
    locateTools();
}

void AppController::encode(int targetSizeMiB,
                           qint64 startMs,
                           qint64 endMs,
                           bool preferHardwareEncoder,
                           bool deleteCacheAfterEncoding)
{
    if (m_busy) {
        return;
    }
    if (!hasSelectedFile()) {
        fail(QStringLiteral("エラー"), QStringLiteral("ファイルを選択してください。"));
        return;
    }
    if (targetSizeMiB <= 0) {
        fail(QStringLiteral("構文エラー"), QStringLiteral("目標ファイルサイズには1以上の整数を入力してください。"));
        return;
    }

    locateTools();
    if (!toolsReady()) {
        fail(QStringLiteral("FFmpeg が必要です"), toolStatus());
        return;
    }
    if ((startMs >= 0 || endMs >= 0) && !(startMs >= 0 && endMs > startMs)) {
        fail(QStringLiteral("トリミングエラー"), QStringLiteral("終了位置は開始位置より後に設定してください。"));
        return;
    }

    m_cacheFilePath.clear();
    m_deleteCacheAfterEncoding = deleteCacheAfterEncoding;
    m_latestOutputPath.clear();
    probeDuration(targetSizeMiB, startMs, endMs, preferHardwareEncoder);
}

void AppController::cancelEncoding()
{
    if (!m_busy) {
        return;
    }
    setBusy(false);
    const bool cacheCreationWasRunning = m_cacheProcess.state() != QProcess::NotRunning;
    if (m_probeProcess.state() != QProcess::NotRunning) {
        disconnect(&m_probeProcess, nullptr, this, nullptr);
        m_probeProcess.kill();
        m_probeProcess.waitForFinished(1000);
    }
    if (cacheCreationWasRunning) {
        m_cacheProcess.kill();
        m_cacheProcess.waitForFinished(1000);
    }
    if (m_encodeProcess.state() != QProcess::NotRunning) {
        m_encodeProcess.kill();
        m_encodeProcess.waitForFinished(1000);
    }
    if (!m_latestOutputPath.isEmpty()) {
        QFile::remove(m_latestOutputPath);
    }
    if (cacheCreationWasRunning) {
        removeCacheFile();
    }
    setProgress(0.0);
    setStatusText(QStringLiteral("エンコード！"));
    m_encodingAttempts.clear();
    m_encodingAttemptLabels.clear();
}

void AppController::revealLatestOutput()
{
    if (m_latestOutputPath.isEmpty() || !QFileInfo::exists(m_latestOutputPath)) {
        return;
    }

#ifdef Q_OS_WIN
    const QString nativePath = QDir::toNativeSeparators(m_latestOutputPath);
    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool comAvailable = SUCCEEDED(comResult) || comResult == RPC_E_CHANGED_MODE;
    HRESULT selectResult = E_FAIL;

    if (comAvailable) {
        PIDLIST_ABSOLUTE itemIdList = ILCreateFromPathW(
            reinterpret_cast<PCWSTR>(nativePath.utf16()));
        if (itemIdList != nullptr) {
            selectResult = SHOpenFolderAndSelectItems(itemIdList, 0, nullptr, 0);
            ILFree(itemIdList);
        }
    }

    if (SUCCEEDED(comResult)) {
        CoUninitialize();
    }

    if (FAILED(selectResult)) {
        QProcess::startDetached(QStringLiteral("explorer.exe"),
                                {QStringLiteral("/select,"), nativePath});
    }
#elif defined(Q_OS_MACOS)
    QProcess::startDetached(QStringLiteral("/usr/bin/open"),
                            {QStringLiteral("-R"), m_latestOutputPath});
#else
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(m_latestOutputPath).absolutePath()));
#endif
}

void AppController::locateTools()
{
    m_ffmpegPath = locateTool(QStringLiteral("ffmpeg"));
    m_ffprobePath = locateTool(QStringLiteral("ffprobe"));
    emit toolsChanged();
}

QString AppController::locateTool(const QString &baseName) const
{
#ifdef Q_OS_WIN
    const QString fileName = baseName + QStringLiteral(".exe");
#else
    const QString fileName = baseName;
#endif

    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    const QString appDir = QCoreApplication::applicationDirPath();
    const QStringList candidates {
        QDir(appData).filePath(QStringLiteral("tools/ffmpeg/current/") + fileName),
        QDir(appDir).filePath(QStringLiteral("tools/ffmpeg/") + fileName),
        QDir(appDir).filePath(fileName)
    };

    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.exists() && info.isFile() && info.isExecutable()) {
            return info.absoluteFilePath();
        }
    }

    return QStandardPaths::findExecutable(fileName);
}

void AppController::probeDuration(int targetSizeMiB,
                                  qint64 startMs,
                                  qint64 endMs,
                                  bool preferHardwareEncoder)
{
    setBusy(true);
    setProgress(0.0);
    setStatusText(QStringLiteral("動画を解析中..."));

    disconnect(&m_probeProcess, nullptr, this, nullptr);
    connect(&m_probeProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this, targetSizeMiB, startMs, endMs, preferHardwareEncoder](int exitCode,
                                                                         QProcess::ExitStatus exitStatus) {
                disconnect(&m_probeProcess, nullptr, this, nullptr);
                if (exitStatus != QProcess::NormalExit || exitCode != 0) {
                    setBusy(false);
                    fail(QStringLiteral("動画解析失敗"),
                         QString::fromUtf8(m_probeProcess.readAllStandardError()).trimmed());
                    return;
                }

                bool ok = false;
                const double seconds = QString::fromUtf8(m_probeProcess.readAllStandardOutput()).trimmed().toDouble(&ok);
                const qint64 fullDurationMs = qRound64(seconds * 1000.0);
                const qint64 durationMs = startMs >= 0 ? endMs - startMs : fullDurationMs;
                if (!ok || durationMs <= 0) {
                    setBusy(false);
                    fail(QStringLiteral("動画解析失敗"), QStringLiteral("動画の長さを取得できませんでした。"));
                    return;
                }

                startEncoding(targetSizeMiB,
                              startMs,
                              endMs,
                              durationMs,
                              preferHardwareEncoder);
            },
            Qt::SingleShotConnection);

    m_probeProcess.start(m_ffprobePath,
                         {QStringLiteral("-v"), QStringLiteral("error"),
                          QStringLiteral("-show_entries"), QStringLiteral("format=duration"),
                          QStringLiteral("-of"), QStringLiteral("default=noprint_wrappers=1:nokey=1"),
                          m_selectedFilePath});

    if (!m_probeProcess.waitForStarted(5000)) {
        disconnect(&m_probeProcess, nullptr, this, nullptr);
        setBusy(false);
        fail(QStringLiteral("FFprobe 起動失敗"), m_probeProcess.errorString());
    }
}

void AppController::startEncoding(int targetSizeMiB,
                                  qint64 startMs,
                                  qint64 endMs,
                                  qint64 durationMs,
                                  bool preferHardwareEncoder)
{
    const double durationSeconds = static_cast<double>(durationMs) / 1000.0;
    const double targetBits = static_cast<double>(targetSizeMiB) * 1'000'000.0 * 8.0;
    const int totalBitrateKbps = static_cast<int>(std::floor(
        targetBits * containerSafetyFactor / durationSeconds / 1000.0));
    const int videoBitrateKbps = totalBitrateKbps - audioBitrateKbps;

    if (videoBitrateKbps < minimumVideoBitrateKbps) {
        setBusy(false);
        fail(QStringLiteral("容量オーバー"),
             QStringLiteral("この動画を %1 MB 未満に変換することはできません。").arg(targetSizeMiB));
        return;
    }

    const QString outputPath = buildOutputPath(targetSizeMiB, startMs, endMs);
    if (QFileInfo::exists(outputPath)) {
        setBusy(false);
        fail(QStringLiteral("ファイルが既に存在します"),
             QStringLiteral("出力先のファイル名を変更するか、既存ファイルを移動してください。"));
        return;
    }

    m_latestOutputPath = outputPath;
    m_activeDurationMs = durationMs;
    m_pendingVideoBitrateKbps = videoBitrateKbps;
    m_hardwareEncodingRequested = preferHardwareEncoder;
    m_progressBuffer.clear();

    if (startMs >= 0) {
        const QFileInfo input(m_selectedFilePath);
        const QDir inputDirectory(input.absolutePath());
        do {
            const QString cacheId = QUuid::createUuid()
                                        .toString(QUuid::WithoutBraces)
                                        .section(QLatin1Char('-'), 0, 0);
            const QString cacheName = QStringLiteral("%1_%2M_%3.mp4")
                                          .arg(input.completeBaseName())
                                          .arg(targetSizeMiB)
                                          .arg(cacheId);
            m_cacheFilePath = inputDirectory.filePath(cacheName);
        } while (QFileInfo::exists(m_cacheFilePath));

        m_encodingInputPath = m_cacheFilePath;
        startCacheCreation(startMs, endMs);
        return;
    }

    m_encodingInputPath = m_selectedFilePath;
    prepareEncodingAttempts(videoBitrateKbps);
}

void AppController::startCacheCreation(qint64 startMs, qint64 endMs)
{
    m_cacheProgressBuffer.clear();
    m_cacheErrorBuffer.clear();
    setStatusText(QStringLiteral("無劣化の一時ファイルを作成中: 0.0%"));

    const QStringList arguments {
        QStringLiteral("-y"),
        QStringLiteral("-i"), m_selectedFilePath,
        QStringLiteral("-ss"), formatTime(startMs),
        QStringLiteral("-t"), formatTime(endMs - startMs),
        QStringLiteral("-c"), QStringLiteral("copy"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1"),
        QStringLiteral("-nostats"),
        m_cacheFilePath
    };
    m_cacheProcess.start(m_ffmpegPath, arguments);

    if (!m_cacheProcess.waitForStarted(5000)) {
        setBusy(false);
        removeCacheFile();
        fail(QStringLiteral("キャッシュ作成失敗"), m_cacheProcess.errorString());
    }
}

void AppController::prepareEncodingAttempts(int videoBitrateKbps)
{
    auto argumentsForEncoder = [this, videoBitrateKbps](const QString &encoder) {
        QStringList arguments {QStringLiteral("-y")};
        arguments << QStringLiteral("-i") << m_encodingInputPath;
        arguments << QStringLiteral("-c:v") << encoder;
        if (encoder == QStringLiteral("libx264")) {
            arguments << QStringLiteral("-preset") << QStringLiteral("medium");
        }
        arguments << QStringLiteral("-b:v") << QStringLiteral("%1k").arg(videoBitrateKbps)
                  << QStringLiteral("-maxrate") << QStringLiteral("%1k").arg(videoBitrateKbps + 5)
                  << QStringLiteral("-bufsize") << QStringLiteral("%1k").arg(videoBitrateKbps * 2)
                  << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p")
                  << QStringLiteral("-c:a") << QStringLiteral("aac")
                  << QStringLiteral("-b:a") << QStringLiteral("%1k").arg(audioBitrateKbps)
                  << QStringLiteral("-movflags") << QStringLiteral("+faststart")
                  << QStringLiteral("-progress") << QStringLiteral("pipe:1")
                  << QStringLiteral("-nostats")
                  << m_latestOutputPath;
        return arguments;
    };

    m_encodingAttempts.clear();
    m_encodingAttemptLabels.clear();
    const QStringList hardwareEncoders = m_hardwareEncodingRequested
        ? availableHardwareEncoders()
        : QStringList{};
    for (const QString &encoder : hardwareEncoders) {
        m_encodingAttempts.append(argumentsForEncoder(encoder));
        if (encoder == QStringLiteral("h264_nvenc")) {
            m_encodingAttemptLabels.append(QStringLiteral("NVIDIA GPU"));
        } else if (encoder == QStringLiteral("h264_qsv")) {
            m_encodingAttemptLabels.append(QStringLiteral("Intel GPU"));
        } else if (encoder == QStringLiteral("h264_amf")) {
            m_encodingAttemptLabels.append(QStringLiteral("AMD GPU"));
        } else {
            m_encodingAttemptLabels.append(QStringLiteral("Apple VideoToolbox"));
        }
    }
    m_hardwareEncodingAttemptCount = m_encodingAttempts.size();
    m_encodingAttempts.append(argumentsForEncoder(QStringLiteral("libx264")));
    m_encodingAttemptLabels.append(QStringLiteral("CPU"));
    m_currentEncodingAttempt = 0;
    m_progressBuffer.clear();
    startCurrentEncodingAttempt();
}

void AppController::startCurrentEncodingAttempt()
{
    if (m_currentEncodingAttempt >= m_encodingAttempts.size()) {
        setBusy(false);
        fail(QStringLiteral("エンコード失敗"), QStringLiteral("利用できるエンコーダーがありません。"));
        return;
    }

    m_activeEncoderLabel = m_encodingAttemptLabels.at(m_currentEncodingAttempt);
    if (m_hardwareEncodingRequested
        && m_currentEncodingAttempt >= m_hardwareEncodingAttemptCount) {
        setStatusText(QStringLiteral("GPUを利用できないためCPUでエンコード中: 0.0%"));
    } else {
        setStatusText(QStringLiteral("エンコード中（%1）: 0.0%").arg(m_activeEncoderLabel));
    }
    m_encodeProcess.start(m_ffmpegPath, m_encodingAttempts.at(m_currentEncodingAttempt));

    if (!m_encodeProcess.waitForStarted(5000)) {
        setBusy(false);
        fail(QStringLiteral("FFmpeg 起動失敗"), m_encodeProcess.errorString());
    }
}

QStringList AppController::availableHardwareEncoders() const
{
    QProcess encoderProbe;
    encoderProbe.setProcessChannelMode(QProcess::MergedChannels);
    encoderProbe.start(m_ffmpegPath,
                       {QStringLiteral("-hide_banner"), QStringLiteral("-encoders")});
    if (!encoderProbe.waitForStarted(3000) || !encoderProbe.waitForFinished(10000)) {
        encoderProbe.kill();
        encoderProbe.waitForFinished(1000);
        return {};
    }

    const QByteArray encoderList = encoderProbe.readAllStandardOutput();
    QStringList candidates;
#ifdef Q_OS_WIN
    candidates << QStringLiteral("h264_nvenc")
               << QStringLiteral("h264_qsv")
               << QStringLiteral("h264_amf");
#elif defined(Q_OS_MACOS)
    candidates << QStringLiteral("h264_videotoolbox");
#endif

    QStringList available;
    for (const QString &candidate : candidates) {
        if (encoderList.contains((QByteArrayLiteral(" ")
                                  + candidate.toUtf8()
                                  + QByteArrayLiteral(" ")))) {
            available.append(candidate);
        }
    }
    return available;
}

void AppController::consumeCacheProgressOutput()
{
    m_cacheProgressBuffer += m_cacheProcess.readAllStandardOutput();
    qsizetype newline = -1;
    while ((newline = m_cacheProgressBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_cacheProgressBuffer.left(newline).trimmed();
        m_cacheProgressBuffer.remove(0, newline + 1);

        const qsizetype separator = line.indexOf('=');
        if (separator <= 0) {
            continue;
        }
        const QByteArray key = line.left(separator);
        if (key != "out_time_us" && key != "out_time_ms") {
            continue;
        }

        bool ok = false;
        const qint64 microseconds = line.mid(separator + 1).toLongLong(&ok);
        if (ok && m_activeDurationMs > 0) {
            const double value = static_cast<double>(microseconds)
                / (static_cast<double>(m_activeDurationMs) * 1000.0);
            setProgress(std::clamp(value, 0.0, 1.0));
            setStatusText(QStringLiteral("無劣化の一時ファイルを作成中: %1%")
                              .arg(m_progress * 100.0, 0, 'f', 1));
        }
    }
}

void AppController::consumeProgressOutput()
{
    m_progressBuffer += m_encodeProcess.readAllStandardOutput();
    qsizetype newline = -1;
    while ((newline = m_progressBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_progressBuffer.left(newline).trimmed();
        m_progressBuffer.remove(0, newline + 1);

        const qsizetype separator = line.indexOf('=');
        if (separator <= 0) {
            continue;
        }
        const QByteArray key = line.left(separator);
        const QByteArray value = line.mid(separator + 1);
        if (key == "out_time_us" || key == "out_time_ms") {
            bool ok = false;
            const qint64 microseconds = value.toLongLong(&ok);
            if (ok && m_activeDurationMs > 0) {
                const double value = static_cast<double>(microseconds)
                    / (static_cast<double>(m_activeDurationMs) * 1000.0);
                setProgress(std::clamp(value, 0.0, 1.0));
                if (m_hardwareEncodingRequested
                    && m_currentEncodingAttempt >= m_hardwareEncodingAttemptCount) {
                    setStatusText(QStringLiteral("GPUを利用できないためCPUでエンコード中: %1%")
                                      .arg(m_progress * 100.0, 0, 'f', 1));
                } else {
                    setStatusText(QStringLiteral("エンコード中（%1）: %2%")
                                      .arg(m_activeEncoderLabel)
                                      .arg(m_progress * 100.0, 0, 'f', 1));
                }
            }
        }
    }
}

void AppController::removeCacheFile()
{
    if (m_cacheFilePath.isEmpty()) {
        return;
    }
    QFile::remove(m_cacheFilePath);
    m_cacheFilePath.clear();
}

void AppController::setBusy(bool value)
{
    if (m_busy == value) {
        return;
    }
    m_busy = value;
    emit busyChanged();
}

void AppController::setProgress(double value)
{
    if (qFuzzyCompare(m_progress, value)) {
        return;
    }
    m_progress = value;
    emit progressChanged();
}

void AppController::setStatusText(const QString &value)
{
    if (m_statusText == value) {
        return;
    }
    m_statusText = value;
    emit statusTextChanged();
}

void AppController::fail(const QString &title, const QString &message)
{
    setStatusText(QStringLiteral("エンコード！"));
    emit errorOccurred(title, message.isEmpty() ? QStringLiteral("不明なエラーが発生しました。") : message);
}

QString AppController::buildOutputPath(int targetSizeMiB, qint64 startMs, qint64 endMs) const
{
    const QFileInfo input(m_selectedFilePath);
    QString suffix = QStringLiteral("_%1M").arg(targetSizeMiB);
    if (startMs >= 0) {
        auto compactTime = [](qint64 value) {
            QString result = formatTime(value);
            result.remove(QLatin1Char(':'));
            result.remove(QLatin1Char('.'));
            return result;
        };
        suffix += QStringLiteral("_%1-%2").arg(compactTime(startMs), compactTime(endMs));
    }
    return QDir(input.absolutePath()).filePath(input.completeBaseName() + suffix + QStringLiteral(".mp4"));
}

QString AppController::formatTime(qint64 milliseconds)
{
    const qint64 totalSeconds = milliseconds / 1000;
    const qint64 hours = totalSeconds / 3600;
    const qint64 minutes = (totalSeconds % 3600) / 60;
    const qint64 seconds = totalSeconds % 60;
    const qint64 millis = milliseconds % 1000;
    return QStringLiteral("%1:%2:%3.%4")
        .arg(hours, 2, 10, QLatin1Char('0'))
        .arg(minutes, 2, 10, QLatin1Char('0'))
        .arg(seconds, 2, 10, QLatin1Char('0'))
        .arg(millis, 3, 10, QLatin1Char('0'));
}
