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
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>
#include <QWindow>
#include <QUuid>
#include <QVersionNumber>
#include <QVariantMap>
#include <QtGlobal>

#include <algorithm>
#include <cmath>

namespace {
constexpr int audioBitrateKbps = 96;
constexpr int minimumVideoBitrateKbps = 50;
constexpr double containerSafetyFactor = 0.97;
constexpr double minimumAudioGainDb = -30.0;
constexpr double maximumAudioGainDb = 30.0;
constexpr double minimumAudioLevelDb = -60.0;
// Stored waveform resolution. Far finer than a single view needs, so zooming
// in uncovers detail instead of magnifying an overview.
constexpr int audioWaveformBucketMs = 2;
// Ceiling on the stored buckets. Long files coarsen past this rather than
// growing without bound; 900k buckets is about 30 minutes at 2 ms.
constexpr int audioWaveformMaxBuckets = 900000;
// Decoding rate for waveform analysis. Well above what the picture resolves,
// but low enough to keep the pipe cheap on long files.
constexpr int audioWaveformSampleRateHz = 22050;

struct ReleaseVersion {
    QVersionNumber baseVersion;
    QString prereleaseIdentity;
    qint64 snapshotBuildNumber = -1;
    bool prerelease = false;
    bool valid = false;
};

ReleaseVersion parseReleaseVersion(QString version)
{
    version = version.trimmed();
    static const QRegularExpression pattern(
        QStringLiteral(R"(^v?(\d+)\.(\d+)\.(\d+)(?:(?:-SNAPSHOT_(\d+))|(?:-PRE_([0-9a-f]{7,40})))?(?:\+(\d+))?$)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = pattern.match(version);
    if (!match.hasMatch()) {
        return {};
    }

    bool majorOk = false;
    bool minorOk = false;
    bool patchOk = false;
    const int major = match.captured(1).toInt(&majorOk);
    const int minor = match.captured(2).toInt(&minorOk);
    const int patch = match.captured(3).toInt(&patchOk);
    if (!majorOk || !minorOk || !patchOk) {
        return {};
    }

    ReleaseVersion result;
    result.baseVersion = QVersionNumber(major, minor, patch);
    const QString snapshotBuild = match.captured(4);
    const QString legacyCommit = match.captured(5).toLower();
    if (!snapshotBuild.isEmpty()) {
        bool snapshotOk = false;
        result.snapshotBuildNumber = snapshotBuild.toLongLong(&snapshotOk);
        if (!snapshotOk) {
            return {};
        }
        result.prereleaseIdentity = snapshotBuild;
    } else if (!legacyCommit.isEmpty()) {
        // Keep older PRE releases readable during the SNAPSHOT transition.
        result.prereleaseIdentity = legacyCommit;
    }
    result.prerelease = !result.prereleaseIdentity.isEmpty();
    result.valid = true;
    return result;
}

int compareReleaseChannels(const ReleaseVersion &left, const ReleaseVersion &right)
{
    const int baseComparison = QVersionNumber::compare(left.baseVersion, right.baseVersion);
    if (baseComparison != 0) {
        return baseComparison;
    }
    if (left.prerelease != right.prerelease) {
        // A stable release supersedes snapshots of the same target version.
        return left.prerelease ? -1 : 1;
    }
    if (left.prerelease
        && left.snapshotBuildNumber >= 0
        && right.snapshotBuildNumber >= 0
        && left.snapshotBuildNumber != right.snapshotBuildNumber) {
        return left.snapshotBuildNumber > right.snapshotBuildNumber ? 1 : -1;
    }
    return 0;
}

bool isReleaseNewerThanCurrent(const ReleaseVersion &release,
                               const ReleaseVersion &current)
{
    const int channelComparison = compareReleaseChannels(release, current);
    if (channelComparison != 0) {
        return channelComparison > 0;
    }
    return false;
}

bool isValidReleaseUrl(const QUrl &url)
{
    return url.isValid()
        && url.scheme() == QStringLiteral("https")
        && url.host().compare(QStringLiteral("github.com"), Qt::CaseInsensitive) == 0;
}

QString readEmbeddedTextFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QStringLiteral("ライセンス情報を読み込めませんでした。");
    }
    return QString::fromUtf8(file.readAll());
}
}

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_audioTrackModel = new AudioTrackModel(&m_audioTracks, this);
    m_prereleaseBuild = parseReleaseVersion(currentVersion()).prerelease;
    const QSettings settings;
    m_includePrereleaseUpdates = m_prereleaseBuild
        || settings.value(QStringLiteral("updates/includePrereleases"), false).toBool();

    m_waveformProcess.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_waveformProcess, &QProcess::readyReadStandardOutput,
            this, &AppController::readWaveformSamples);
    connect(&m_waveformProcess, &QProcess::finished,
            this, &AppController::finishWaveformTrack);

    m_probeProcess.setProcessChannelMode(QProcess::SeparateChannels);
    m_trackProbeProcess.setProcessChannelMode(QProcess::SeparateChannels);
    m_audioAnalysisProcess.setProcessChannelMode(QProcess::SeparateChannels);
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

    connect(&m_trackProbeProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
                m_tracksLoading = false;
                if (exitStatus == QProcess::NormalExit && exitCode == 0) {
                    parseMediaTracks(m_trackProbeProcess.readAllStandardOutput());
                } else {
                    m_videoTracks.clear();
                    m_audioTracks.clear();
                    m_audioTrackLevels.clear();
                    m_selectedVideoTrack = 0;
                    m_monitoredAudioTrack = -1;
                    m_mediaDurationMs = 0;
                    clearAudioWaveforms();
                    emit audioTrackLevelsChanged();
                    emit audioMonitorChanged();
                }
                m_audioTrackModel->notifyReset();
                emit mediaTracksChanged();
            });

    connect(&m_audioAnalysisProcess, &QProcess::readyReadStandardError, this, [this] {
        m_audioAnalysisOutput += m_audioAnalysisProcess.readAllStandardError();
    });
    connect(&m_audioAnalysisProcess, &QProcess::readyReadStandardOutput,
            this, &AppController::consumeAudioAnalysisProgressOutput);
    connect(&m_audioAnalysisProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
                consumeAudioAnalysisProgressOutput();
                m_audioAnalysisOutput += m_audioAnalysisProcess.readAllStandardError();
                const int trackIndex = m_audioAnalysisQueue.isEmpty()
                    ? -1
                    : m_audioAnalysisQueue.takeFirst();

                static const QRegularExpression meanVolumePattern(
                    QStringLiteral(R"(mean_volume:\s*([-+]?\d+(?:\.\d+)?)\s*dB)"),
                    QRegularExpression::CaseInsensitiveOption);
                const QRegularExpressionMatch match = meanVolumePattern.match(
                    QString::fromUtf8(m_audioAnalysisOutput));
                if (exitStatus == QProcess::NormalExit
                    && exitCode == 0
                    && trackIndex >= 0
                    && trackIndex < m_audioTracks.size()
                    && match.hasMatch()) {
                    bool ok = false;
                    const double meanDb = match.captured(1).toDouble(&ok);
                    if (ok) {
                        AudioTrackInfo &track = m_audioTracks[trackIndex];
                        track.measuredMeanDb = meanDb;
                        track.hasMeasurement = true;
                        ++m_audioAnalysisSuccessCount;
                    }
                }

                m_audioAnalysisCurrentTrack = -1;
                m_audioTrackModel->notifyTrackChanged(
                    trackIndex,
                    {AudioTrackModel::HasMeasurementRole, AudioTrackModel::MeanVolumeDbRole});
                startNextAudioAnalysis();
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

QVariantList AppController::videoTracks() const
{
    QVariantList result;
    for (qsizetype index = 0; index < m_videoTracks.size(); ++index) {
        const VideoTrackInfo &track = m_videoTracks.at(index);
        QStringList details;
        if (!track.codec.isEmpty()) {
            details.append(track.codec.toUpper());
        }
        if (track.width > 0 && track.height > 0) {
            details.append(QStringLiteral("%1×%2").arg(track.width).arg(track.height));
        }
        if (!track.language.isEmpty() && track.language != QStringLiteral("und")) {
            details.append(track.language);
        }
        if (!track.title.isEmpty()) {
            details.append(track.title);
        }

        QVariantMap item;
        item.insert(QStringLiteral("index"), index);
        item.insert(QStringLiteral("streamIndex"), track.streamIndex);
        item.insert(QStringLiteral("label"),
                    QStringLiteral("%1: %2")
                        .arg(index)
                        .arg(details.isEmpty() ? QStringLiteral("動画トラック")
                                               : details.join(QStringLiteral(" · "))));
        item.insert(QStringLiteral("selected"), index == m_selectedVideoTrack);
        result.append(item);
    }
    return result;
}

AudioTrackModel *AppController::audioTrackModel() const
{
    return m_audioTrackModel;
}

QVariantList AppController::audioTrackLevels() const
{
    QVariantList result;
    result.reserve(m_audioTrackLevels.size());
    for (const double levelDb : m_audioTrackLevels) {
        result.append(levelDb);
    }
    return result;
}

int AppController::selectedVideoTrack() const
{
    return m_selectedVideoTrack;
}

int AppController::monitoredAudioTrack() const
{
    return m_monitoredAudioTrack;
}

bool AppController::tracksLoading() const
{
    return m_tracksLoading;
}

bool AppController::analyzingAudio() const
{
    return m_analyzingAudio;
}

QString AppController::audioAnalysisStatus() const
{
    return m_audioAnalysisStatus;
}

double AppController::audioAnalysisTrackProgress() const
{
    return m_audioAnalysisTrackProgress;
}

QString AppController::licenseText() const
{
    return readEmbeddedTextFile(QStringLiteral(":/licenses/LICENSE.md"));
}

QString AppController::thirdPartyNoticesText() const
{
    return readEmbeddedTextFile(QStringLiteral(":/licenses/THIRD_PARTY_NOTICES.md"));
}

bool AppController::checkingForUpdates() const
{
    return m_checkingForUpdates;
}

bool AppController::updateAvailable() const
{
    return m_updateAvailable;
}

bool AppController::includePrereleaseUpdates() const
{
    return m_includePrereleaseUpdates;
}

bool AppController::prereleaseBuild() const
{
    return m_prereleaseBuild;
}

QString AppController::currentVersion() const
{
    return QCoreApplication::applicationVersion();
}

QString AppController::latestVersion() const
{
    return m_latestVersion;
}

QUrl AppController::latestReleaseUrl() const
{
    return m_latestReleaseUrl;
}

QString AppController::updateStatus() const
{
    return m_updateStatus;
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
    if (m_trackProbeProcess.state() != QProcess::NotRunning) {
        m_trackProbeProcess.kill();
        m_trackProbeProcess.waitForFinished(1000);
    }
    m_analyzingAudio = false;
    m_audioAnalysisQueue.clear();
    if (m_audioAnalysisProcess.state() != QProcess::NotRunning) {
        m_audioAnalysisProcess.kill();
        m_audioAnalysisProcess.waitForFinished(1000);
    }
    m_videoTracks.clear();
    m_audioTracks.clear();
    m_audioTrackLevels.clear();
    m_selectedVideoTrack = 0;
    m_monitoredAudioTrack = -1;
    m_mediaDurationMs = 0;
    m_audioAnalysisTrackProgress = 0.0;
    m_audioAnalysisStatus.clear();
    clearAudioWaveforms();
    if (m_audioMeteringAvailable) {
        m_audioMeteringAvailable = false;
        emit audioMeteringAvailableChanged();
    }
    emit selectedFileChanged();
    m_audioTrackModel->notifyReset();
    emit mediaTracksChanged();
    emit audioTrackLevelsChanged();
    emit audioMonitorChanged();
    emit audioAnalysisChanged();
    probeMediaTracks();
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
    if (m_trackProbeProcess.state() != QProcess::NotRunning) {
        m_trackProbeProcess.kill();
        m_trackProbeProcess.waitForFinished(1000);
    }
    m_analyzingAudio = false;
    m_audioAnalysisQueue.clear();
    if (m_audioAnalysisProcess.state() != QProcess::NotRunning) {
        m_audioAnalysisProcess.kill();
        m_audioAnalysisProcess.waitForFinished(1000);
    }
    m_selectedFilePath.clear();
    m_videoTracks.clear();
    m_audioTracks.clear();
    m_audioTrackLevels.clear();
    m_selectedVideoTrack = 0;
    m_monitoredAudioTrack = -1;
    m_mediaDurationMs = 0;
    m_audioAnalysisTrackProgress = 0.0;
    m_tracksLoading = false;
    m_audioAnalysisStatus.clear();
    clearAudioWaveforms();
    if (m_audioMeteringAvailable) {
        m_audioMeteringAvailable = false;
        emit audioMeteringAvailableChanged();
    }
    emit selectedFileChanged();
    m_audioTrackModel->notifyReset();
    emit mediaTracksChanged();
    emit audioTrackLevelsChanged();
    emit audioMonitorChanged();
    emit audioAnalysisChanged();
}

void AppController::refreshTools()
{
    locateTools();
    if (hasSelectedFile() && m_videoTracks.isEmpty() && m_audioTracks.isEmpty()) {
        probeMediaTracks();
    }
}

void AppController::setSelectedVideoTrack(int trackIndex)
{
    if (m_busy || trackIndex < 0 || trackIndex >= m_videoTracks.size()
        || m_selectedVideoTrack == trackIndex) {
        return;
    }
    m_selectedVideoTrack = trackIndex;
    emit mediaTracksChanged();
}

void AppController::setAudioTrackSelected(int trackIndex, bool selected)
{
    if (m_busy || m_analyzingAudio || trackIndex < 0 || trackIndex >= m_audioTracks.size()
        || m_audioTracks.at(trackIndex).selected == selected) {
        return;
    }
    m_audioTracks[trackIndex].selected = selected;
    if (!selected && m_monitoredAudioTrack == trackIndex) {
        m_monitoredAudioTrack = -1;
        resetAudioTrackLevels();
        emit audioMonitorChanged();
    }
    m_audioTrackModel->notifyTrackChanged(trackIndex, {AudioTrackModel::SelectedRole});
    refreshMixWaveform();
}

void AppController::setAllAudioTracksSelected(bool selected)
{
    if (m_busy || m_analyzingAudio) {
        return;
    }
    bool changed = false;
    for (AudioTrackInfo &track : m_audioTracks) {
        if (track.selected != selected) {
            track.selected = selected;
            changed = true;
        }
    }
    if (changed) {
        if (!selected && m_monitoredAudioTrack >= 0) {
            m_monitoredAudioTrack = -1;
            resetAudioTrackLevels();
            emit audioMonitorChanged();
        }
        m_audioTrackModel->notifyAllTracksChanged({AudioTrackModel::SelectedRole});
        refreshMixWaveform();
    }
}

void AppController::setAudioTrackGainDb(int trackIndex, double gainDb)
{
    if (m_busy || m_analyzingAudio || trackIndex < 0 || trackIndex >= m_audioTracks.size()
        || !std::isfinite(gainDb)) {
        return;
    }
    const double adjustedGain = std::clamp(gainDb, minimumAudioGainDb, maximumAudioGainDb);
    if (qFuzzyCompare(m_audioTracks.at(trackIndex).gainDb, adjustedGain)) {
        return;
    }
    m_audioTracks[trackIndex].gainDb = adjustedGain;
    m_audioTrackModel->notifyTrackChanged(trackIndex, {AudioTrackModel::GainDbRole});
    refreshMixWaveform();
}

void AppController::setAudioTrackLevelDb(int trackIndex, double levelDb)
{
    if (trackIndex < 0 || trackIndex >= m_audioTrackLevels.size() || !std::isfinite(levelDb)) {
        return;
    }
    const double adjustedLevel = std::clamp(levelDb, minimumAudioLevelDb, 0.0);
    if (std::abs(m_audioTrackLevels.at(trackIndex) - adjustedLevel) < 0.1) {
        return;
    }
    m_audioTrackLevels[trackIndex] = adjustedLevel;
    emit audioTrackLevelsChanged();
}

void AppController::resetAudioTrackLevels()
{
    bool changed = false;
    for (double &levelDb : m_audioTrackLevels) {
        if (!qFuzzyCompare(levelDb, minimumAudioLevelDb)) {
            levelDb = minimumAudioLevelDb;
            changed = true;
        }
    }
    if (changed) {
        emit audioTrackLevelsChanged();
    }
}

bool AppController::audioWaveformsAnalyzing() const
{
    return m_audioWaveformsAnalyzing;
}

bool AppController::audioMeteringAvailable() const
{
    return m_audioMeteringAvailable;
}

void AppController::setWaveformsAnalyzing(bool analyzing)
{
    if (m_audioWaveformsAnalyzing == analyzing) {
        return;
    }
    m_audioWaveformsAnalyzing = analyzing;
    emit audioWaveformsAnalyzingChanged();
}

void AppController::clearAudioWaveforms()
{
    // Drop the queue and the current track before killing, so the finished
    // signal that the kill delivers cannot start the next decode behind us.
    m_waveformQueue.clear();
    m_waveformTrackIndex = -1;
    if (m_waveformProcess.state() != QProcess::NotRunning) {
        m_waveformProcess.kill();
        m_waveformProcess.waitForFinished(2000);
    }
    m_waveformCarry.clear();
    m_waveformPeaks.clear();

    // An empty waveform reads as "nothing decoded yet" and draws as silence.
    m_audioTrackWaveforms.assign(m_audioTracks.size(), QList<float>());
    m_audioWaveformReady.assign(m_audioTracks.size(), false);
    m_audioMixWaveform.clear();
    m_audioWaveformBuckets = 0;

    setWaveformsAnalyzing(false);
    emit audioWaveformsChanged();
}

bool AppController::audioTrackWaveformReady(int trackIndex) const
{
    return m_audioWaveformReady.value(trackIndex, false);
}

void AppController::startWaveformAnalysis()
{
    if (m_ffmpegPath.isEmpty() || !hasSelectedFile() || m_audioTracks.isEmpty()
        || m_mediaDurationMs <= 0) {
        return;
    }

    m_audioWaveformBuckets = static_cast<int>(std::clamp<qint64>(
        m_mediaDurationMs / audioWaveformBucketMs, 1, audioWaveformMaxBuckets));

    m_waveformQueue.clear();
    for (qsizetype index = 0; index < m_audioTracks.size(); ++index) {
        m_waveformQueue.append(static_cast<int>(index));
    }
    setWaveformsAnalyzing(true);
    startNextWaveformTrack();
}

void AppController::startNextWaveformTrack()
{
    if (m_waveformQueue.isEmpty()) {
        m_waveformTrackIndex = -1;
        setWaveformsAnalyzing(false);
        return;
    }

    // A kill that has not been reaped yet still owns the process; its finished
    // handler calls back here, so the queue is picked up then instead.
    if (m_waveformProcess.state() != QProcess::NotRunning) {
        return;
    }

    m_waveformTrackIndex = m_waveformQueue.takeFirst();
    m_waveformPeaks.fill(0.0f, m_audioWaveformBuckets);
    m_waveformSampleIndex = 0;
    m_waveformCarry.clear();
    m_waveformExpectedSamples = std::max<qint64>(
        1, m_mediaDurationMs * audioWaveformSampleRateHz / 1000);

    // Decode the one track to raw mono PCM on stdout and reduce it to bucket
    // peaks as it arrives, so nothing larger than a read buffer is held.
    m_waveformProcess.start(
        m_ffmpegPath,
        {QStringLiteral("-v"), QStringLiteral("error"),
         QStringLiteral("-nostdin"),
         QStringLiteral("-i"), m_selectedFilePath,
         QStringLiteral("-map"), QStringLiteral("0:a:%1").arg(m_waveformTrackIndex),
         QStringLiteral("-ac"), QStringLiteral("1"),
         QStringLiteral("-ar"), QString::number(audioWaveformSampleRateHz),
         QStringLiteral("-f"), QStringLiteral("s16le"),
         QStringLiteral("-")});
}

void AppController::readWaveformSamples()
{
    const QByteArray chunk = m_waveformCarry + m_waveformProcess.readAllStandardOutput();
    if (m_waveformTrackIndex < 0) {
        m_waveformCarry.clear();
        return;
    }

    const qsizetype usable = chunk.size() - (chunk.size() % 2);
    for (qsizetype offset = 0; offset < usable; offset += 2) {
        // Signed 16-bit little endian, decoded by hand to stay independent of
        // the buffer's alignment and the host byte order.
        const int low = static_cast<quint8>(chunk.at(offset));
        const int high = static_cast<qint8>(chunk.at(offset + 1));
        const float amplitude = std::abs((high << 8) | low) / 32768.0f;

        const qint64 bucket = std::clamp<qint64>(
            m_waveformSampleIndex * m_audioWaveformBuckets / m_waveformExpectedSamples,
            0, m_audioWaveformBuckets - 1);
        if (amplitude > m_waveformPeaks.at(bucket)) {
            m_waveformPeaks[bucket] = amplitude;
        }
        ++m_waveformSampleIndex;
    }
    m_waveformCarry = chunk.mid(usable);
}

void AppController::finishWaveformTrack(int exitCode, QProcess::ExitStatus status)
{
    const int trackIndex = m_waveformTrackIndex;
    m_waveformTrackIndex = -1;

    const bool succeeded = status == QProcess::NormalExit && exitCode == 0
        && trackIndex >= 0 && trackIndex < m_audioTrackWaveforms.size();
    if (succeeded) {
        QList<float> levels;
        levels.reserve(m_waveformPeaks.size());
        for (const float peak : std::as_const(m_waveformPeaks)) {
            levels.append(peak > 0.0f
                              ? std::clamp(20.0f * std::log10(peak),
                                           static_cast<float>(minimumAudioLevelDb), 0.0f)
                              : static_cast<float>(minimumAudioLevelDb));
        }
        m_audioTrackWaveforms[trackIndex] = levels;
        m_audioWaveformReady[trackIndex] = true;
        rebuildMixWaveform();
        emit audioWaveformsChanged();
    }

    m_waveformPeaks.clear();
    m_waveformCarry.clear();
    startNextWaveformTrack();
}

void AppController::rebuildMixWaveform()
{
    // Peaks add in the amplitude domain, which is the worst case the encoder's
    // limiter would have to absorb, so the mix strip matches what it warns about.
    if (m_audioWaveformBuckets <= 0) {
        m_audioMixWaveform.clear();
        return;
    }

    QList<double> amplitudes(m_audioWaveformBuckets, 0.0);
    bool anyContribution = false;

    for (qsizetype index = 0; index < m_audioTracks.size(); ++index) {
        const bool contributes = m_monitoredAudioTrack >= 0
            ? m_monitoredAudioTrack == index
            : m_audioTracks.at(index).selected;
        if (!contributes || !m_audioWaveformReady.value(index, false)) {
            continue;
        }

        const QList<float> &levels = m_audioTrackWaveforms.at(index);
        if (levels.size() != m_audioWaveformBuckets) {
            continue;
        }

        const double gain = std::pow(10.0, m_audioTracks.at(index).gainDb / 20.0);
        for (qsizetype bucket = 0; bucket < m_audioWaveformBuckets; ++bucket) {
            const double levelDb = levels.at(bucket);
            if (levelDb > minimumAudioLevelDb) {
                amplitudes[bucket] += std::pow(10.0, levelDb / 20.0) * gain;
            }
        }
        anyContribution = true;
    }

    if (!anyContribution) {
        m_audioMixWaveform.clear();
        return;
    }

    m_audioMixWaveform.resize(m_audioWaveformBuckets);
    for (qsizetype bucket = 0; bucket < m_audioWaveformBuckets; ++bucket) {
        const double amplitude = amplitudes.at(bucket);
        m_audioMixWaveform[bucket] = static_cast<float>(
            amplitude > 0.0
                ? std::clamp(20.0 * std::log10(amplitude), minimumAudioLevelDb, 0.0)
                : minimumAudioLevelDb);
    }
}

void AppController::refreshMixWaveform()
{
    rebuildMixWaveform();
    emit audioWaveformsChanged();
}

void AppController::reportAudioMeteringAvailable()
{
    if (m_audioMeteringAvailable) {
        return;
    }
    m_audioMeteringAvailable = true;
    emit audioMeteringAvailableChanged();
}

QVariantList AppController::audioWaveformRange(int trackIndex,
                                               double startRatio,
                                               double endRatio,
                                               int buckets) const
{
    QVariantList result;
    const QList<float> &source = trackIndex < 0
        ? m_audioMixWaveform
        : m_audioTrackWaveforms.value(trackIndex);
    if (source.isEmpty() || buckets <= 0 || !std::isfinite(startRatio)
        || !std::isfinite(endRatio)) {
        return result;
    }

    const double from = std::clamp(startRatio, 0.0, 1.0);
    const double to = std::clamp(endRatio, 0.0, 1.0);
    if (to <= from) {
        return result;
    }

    const double first = from * source.size();
    const double span = (to - from) * source.size();
    result.reserve(buckets);
    for (int index = 0; index < buckets; ++index) {
        // Reduce by peak, not by average: a quiet average would hide the
        // transients the picture exists to show once the view is zoomed out.
        const qsizetype begin = std::clamp<qsizetype>(
            static_cast<qsizetype>(first + span * index / buckets),
            0, source.size() - 1);
        qsizetype end = std::clamp<qsizetype>(
            static_cast<qsizetype>(first + span * (index + 1) / buckets),
            0, source.size());
        if (end <= begin) {
            end = begin + 1;
        }

        float peak = static_cast<float>(minimumAudioLevelDb);
        for (qsizetype position = begin; position < end; ++position) {
            peak = std::max(peak, source.at(position));
        }
        result.append(static_cast<double>(peak));
    }
    return result;
}

double AppController::audioTrackLevelDb(int trackIndex) const
{
    return trackIndex >= 0 && trackIndex < m_audioTrackLevels.size()
        ? m_audioTrackLevels.at(trackIndex)
        : minimumAudioLevelDb;
}

double AppController::audioMixLevelDb() const
{
    // The live readout has to come from the meters, not from the file-based
    // waveform, whose last bucket is the end of the track rather than "now".
    // Uncorrelated tracks add in the power domain: two equal ones give +3 dB.
    double mixPower = 0.0;
    for (qsizetype index = 0; index < m_audioTracks.size(); ++index) {
        const bool contributes = m_monitoredAudioTrack >= 0
            ? m_monitoredAudioTrack == index
            : m_audioTracks.at(index).selected;
        const double levelDb = m_audioTrackLevels.value(index, minimumAudioLevelDb);
        if (contributes && levelDb > minimumAudioLevelDb) {
            mixPower += std::pow(10.0, levelDb / 10.0);
        }
    }
    return mixPower > 0.0
        ? std::clamp(10.0 * std::log10(mixPower), minimumAudioLevelDb, 0.0)
        : minimumAudioLevelDb;
}

void AppController::setMonitoredAudioTrack(int trackIndex)
{
    if (trackIndex < -1 || trackIndex >= m_audioTracks.size()
        || (trackIndex >= 0 && !m_audioTracks.at(trackIndex).selected)
        || m_monitoredAudioTrack == trackIndex) {
        return;
    }
    m_monitoredAudioTrack = trackIndex;
    resetAudioTrackLevels();
    // The decoded waveforms stay valid; only which tracks feed the mix changed.
    refreshMixWaveform();
    emit audioMonitorChanged();
}

void AppController::autoAdjustAudioTracks(double targetDb, bool analyzeAllTracks)
{
    if (m_busy || m_analyzingAudio || !toolsReady() || !hasSelectedFile()) {
        return;
    }
    if (!std::isfinite(targetDb) || targetDb < -30.0 || targetDb > 0.0) {
        fail(QStringLiteral("音量解析エラー"),
             QStringLiteral("目標平均音量は -30～0 dBFS の範囲で指定してください。"));
        return;
    }

    if (analyzeAllTracks) {
        for (AudioTrackInfo &track : m_audioTracks) {
            track.selected = true;
        }
        m_audioTrackModel->notifyAllTracksChanged({AudioTrackModel::SelectedRole});
    }

    m_audioAnalysisQueue = selectedAudioTrackIndices();
    if (m_audioAnalysisQueue.isEmpty()) {
        fail(QStringLiteral("音量解析エラー"),
             QStringLiteral("解析する音声トラックを1つ以上選択してください。"));
        return;
    }

    m_audioAnalysisTargetDb = targetDb;
    m_audioAnalysisTotal = m_audioAnalysisQueue.size();
    m_audioAnalysisSuccessCount = 0;
    m_audioAnalysisCurrentTrack = -1;
    m_audioAnalysisCurrentOrdinal = 0;
    m_audioAnalysisTrackProgress = 0.0;
    m_audioAnalysisProgressBuffer.clear();
    for (AudioTrackInfo &track : m_audioTracks) {
        if (track.selected) {
            track.hasMeasurement = false;
            track.hasRecommendation = false;
        }
    }
    m_analyzingAudio = true;
    m_audioAnalysisStatus = QStringLiteral("音量を解析しています…");
    m_audioTrackModel->notifyAllTracksChanged(
        {AudioTrackModel::HasMeasurementRole, AudioTrackModel::HasRecommendationRole});
    emit audioAnalysisChanged();
    startNextAudioAnalysis();
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
    if (m_tracksLoading) {
        fail(QStringLiteral("動画解析中"),
             QStringLiteral("トラック情報の解析が完了してからもう一度実行してください。"));
        return;
    }
    if (m_videoTracks.isEmpty()) {
        fail(QStringLiteral("動画トラックがありません"),
             QStringLiteral("出力できる動画トラックを取得できませんでした。"));
        return;
    }
    if (targetSizeMiB <= 0) {
        fail(QStringLiteral("構文エラー"), QStringLiteral("目標ファイルサイズには 1 以上の整数を入力してください。"));
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

void AppController::checkForUpdates()
{
    if (m_checkingForUpdates) {
        return;
    }

    m_checkingForUpdates = true;
    m_updateAvailable = false;
    m_latestVersion.clear();
    m_latestReleaseUrl.clear();
    const bool includePrereleases = m_includePrereleaseUpdates;
    m_updateStatus = includePrereleases
        ? QStringLiteral("GitHub Release を確認中（プリリリースを含む）...")
        : QStringLiteral("GitHub Release を確認中...");
    emit updateStateChanged();

    const QUrl apiUrl(includePrereleases
        ? QStringLiteral("https://api.github.com/repos/SimplyRin/video-converter/releases?per_page=100")
        : QStringLiteral("https://api.github.com/repos/SimplyRin/video-converter/releases/latest"));
    QNetworkRequest request(apiUrl);
    request.setRawHeader(QByteArrayLiteral("Accept"),
                         QByteArrayLiteral("application/vnd.github+json"));
    request.setRawHeader(QByteArrayLiteral("X-GitHub-Api-Version"),
                         QByteArrayLiteral("2022-11-28"));
    request.setRawHeader(QByteArrayLiteral("User-Agent"),
                         QStringLiteral("DiscordVideo/%1").arg(currentVersion()).toUtf8());
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setTransferTimeout(10000);

    QNetworkReply *reply = m_networkManager.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, includePrereleases] {
        m_checkingForUpdates = false;

        if (reply->error() != QNetworkReply::NoError) {
            m_updateStatus = QStringLiteral("アップデートを確認できませんでした。ネットワーク接続を確認してください。");
            reply->deleteLater();
            emit updateStateChanged();
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(reply->readAll(), &parseError);
        reply->deleteLater();
        const bool expectedDocumentType = includePrereleases
            ? document.isArray()
            : document.isObject();
        if (parseError.error != QJsonParseError::NoError || !expectedDocumentType) {
            m_updateStatus = QStringLiteral("GitHub Release の応答を読み取れませんでした。");
            emit updateStateChanged();
            return;
        }

        QJsonArray releases;
        if (includePrereleases) {
            releases = document.array();
        } else {
            releases.append(document.object());
        }

        QJsonObject selectedRelease;
        ReleaseVersion selectedVersion;
        QString selectedPublishedAt;
        for (const QJsonValue &value : releases) {
            const QJsonObject release = value.toObject();
            if (release.value(QStringLiteral("draft")).toBool()) {
                continue;
            }
            if (release.value(QStringLiteral("prerelease")).toBool()
                && !includePrereleases) {
                continue;
            }

            const QString tag = release.value(QStringLiteral("tag_name")).toString().trimmed();
            const ReleaseVersion candidateVersion = parseReleaseVersion(tag);
            const QUrl candidateUrl(release.value(QStringLiteral("html_url")).toString());
            if (!candidateVersion.valid || !isValidReleaseUrl(candidateUrl)) {
                continue;
            }

            const QString candidatePublishedAt = release.value(QStringLiteral("published_at"))
                                                     .toString();
            const int versionComparison = selectedRelease.isEmpty()
                ? 1
                : compareReleaseChannels(candidateVersion, selectedVersion);
            const bool newerSnapshotWithSameBase = versionComparison == 0
                && candidateVersion.prerelease
                && candidatePublishedAt > selectedPublishedAt;
            if (versionComparison > 0 || newerSnapshotWithSameBase) {
                selectedRelease = release;
                selectedVersion = candidateVersion;
                selectedPublishedAt = candidatePublishedAt;
            }
        }

        const ReleaseVersion installedVersion = parseReleaseVersion(currentVersion());
        if (selectedRelease.isEmpty() || !installedVersion.valid) {
            m_updateStatus = QStringLiteral("GitHub Release のバージョン情報を読み取れませんでした。");
            emit updateStateChanged();
            return;
        }

        const QString tagName = selectedRelease.value(QStringLiteral("tag_name"))
                                    .toString()
                                    .trimmed();
        const QUrl releaseUrl(selectedRelease.value(QStringLiteral("html_url")).toString());
        m_latestVersion = tagName.startsWith(QLatin1Char('v'), Qt::CaseInsensitive)
            ? tagName
            : QStringLiteral("v%1").arg(tagName);
        m_latestReleaseUrl = releaseUrl;
        m_updateAvailable = isReleaseNewerThanCurrent(selectedVersion, installedVersion);
        if (m_updateAvailable) {
            m_updateStatus = QStringLiteral("新しいバージョン %1 を利用できます。")
                                 .arg(m_latestVersion);
        } else {
            m_updateStatus = includePrereleases
                ? QStringLiteral("最新版を使用しています (v%1、プリリリースを含む)。")
                      .arg(currentVersion())
                : QStringLiteral("最新版を使用しています (v%1)。").arg(currentVersion());
        }
        emit updateStateChanged();
    });
}

void AppController::setIncludePrereleaseUpdates(bool include)
{
    if (m_prereleaseBuild) {
        include = true;
    }
    if (m_includePrereleaseUpdates == include) {
        return;
    }

    m_includePrereleaseUpdates = include;
    QSettings settings;
    settings.setValue(QStringLiteral("updates/includePrereleases"), include);
    emit updateStateChanged();
    checkForUpdates();
}

void AppController::openLatestRelease()
{
    const QUrl url = m_latestReleaseUrl.isValid()
        ? m_latestReleaseUrl
        : QUrl(m_includePrereleaseUpdates
                   ? QStringLiteral("https://github.com/SimplyRin/video-converter/releases")
                   : QStringLiteral("https://github.com/SimplyRin/video-converter/releases/latest"));
    QDesktopServices::openUrl(url);
}

void AppController::openProjectRepository()
{
    QDesktopServices::openUrl(
        QUrl(QStringLiteral("https://github.com/SimplyRin/video-converter")));
}

void AppController::keepWindowOnScreen(QWindow *window) const
{
    if (window == nullptr) {
        return;
    }

    // Prefer the parent's screen so a dialog never jumps to another monitor.
    const QWindow *parent = window->transientParent();
    const QScreen *screen = parent != nullptr ? parent->screen() : window->screen();
    if (screen == nullptr) {
        return;
    }

    // geometry() is the client area, so add the frame to keep the title bar
    // itself on screen rather than just the content below it.
    const QMargins frame = window->frameMargins();
    const QRect available = screen->availableGeometry();
    QRect frameRect = window->geometry().marginsAdded(frame);

    if (frameRect.width() <= available.width()) {
        frameRect.moveLeft(std::clamp(frameRect.left(),
                                      available.left(),
                                      available.right() - frameRect.width() + 1));
    } else {
        frameRect.moveLeft(available.left());
    }

    if (frameRect.height() <= available.height()) {
        frameRect.moveTop(std::clamp(frameRect.top(),
                                     available.top(),
                                     available.bottom() - frameRect.height() + 1));
    } else {
        frameRect.moveTop(available.top());
    }

    window->setPosition(frameRect.topLeft() + QPoint(frame.left(), frame.top()));
}

void AppController::dockWindowToRight(QWindow *window, QWindow *anchor) const
{
    if (window == nullptr || anchor == nullptr) {
        return;
    }

    const QScreen *screen = anchor->screen();
    if (screen == nullptr) {
        return;
    }

    const QRect available = screen->availableGeometry();
    const QMargins anchorMargins = anchor->frameMargins();
    const QMargins windowMargins = window->frameMargins();
    QRect anchorFrame = anchor->geometry().marginsAdded(anchorMargins);
    const QRect windowFrame = window->geometry().marginsAdded(windowMargins);

    // Slide the anchor left when the two windows would not fit side by side,
    // otherwise the docked window is clamped back on screen and covers it.
    const int pairWidth = anchorFrame.width() + windowFrame.width();
    if (pairWidth <= available.width()) {
        const int overflow = anchorFrame.left() + pairWidth - 1 - available.right();
        if (overflow > 0) {
            anchorFrame.moveLeft(std::max(available.left(), anchorFrame.left() - overflow));
            anchor->setPosition(anchorFrame.topLeft()
                                + QPoint(anchorMargins.left(), anchorMargins.top()));
        }
    }

    // setPosition() takes the client-area origin, so add the frame back.
    window->setPosition(QPoint(anchorFrame.right() + 1 + windowMargins.left(),
                               anchorFrame.top() + windowMargins.top()));
    keepWindowOnScreen(window);
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

void AppController::probeMediaTracks()
{
    if (!hasSelectedFile() || m_ffprobePath.isEmpty()
        || m_trackProbeProcess.state() != QProcess::NotRunning) {
        return;
    }

    m_tracksLoading = true;
    emit mediaTracksChanged();
    m_trackProbeProcess.start(
        m_ffprobePath,
        {QStringLiteral("-v"), QStringLiteral("error"),
         QStringLiteral("-show_entries"),
         QStringLiteral("stream=index,codec_type,codec_name,width,height,channels,channel_layout,duration:stream_tags=title,language:format=duration"),
         QStringLiteral("-of"), QStringLiteral("json"),
         m_selectedFilePath});

    if (!m_trackProbeProcess.waitForStarted(5000)) {
        m_tracksLoading = false;
        emit mediaTracksChanged();
    }
}

void AppController::parseMediaTracks(const QByteArray &json)
{
    m_videoTracks.clear();
    m_audioTracks.clear();
    m_audioTrackLevels.clear();
    m_selectedVideoTrack = 0;
    m_monitoredAudioTrack = -1;
    m_mediaDurationMs = 0;
    emit audioTrackLevelsChanged();
    emit audioMonitorChanged();

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        return;
    }

    const QJsonObject root = document.object();
    bool durationOk = false;
    const double durationSeconds = root.value(QStringLiteral("format"))
                                       .toObject()
                                       .value(QStringLiteral("duration"))
                                       .toVariant()
                                       .toDouble(&durationOk);
    if (durationOk && std::isfinite(durationSeconds) && durationSeconds > 0.0) {
        m_mediaDurationMs = qRound64(durationSeconds * 1000.0);
    }

    const QJsonArray streams = root.value(QStringLiteral("streams")).toArray();
    for (const QJsonValue &value : streams) {
        const QJsonObject stream = value.toObject();
        if (m_mediaDurationMs <= 0) {
            bool streamDurationOk = false;
            const double streamDurationSeconds = stream.value(QStringLiteral("duration"))
                                                     .toVariant()
                                                     .toDouble(&streamDurationOk);
            if (streamDurationOk && std::isfinite(streamDurationSeconds)
                && streamDurationSeconds > 0.0) {
                m_mediaDurationMs = qRound64(streamDurationSeconds * 1000.0);
            }
        }
        const QString type = stream.value(QStringLiteral("codec_type")).toString();
        const QJsonObject tags = stream.value(QStringLiteral("tags")).toObject();
        if (type == QStringLiteral("video")) {
            VideoTrackInfo track;
            track.streamIndex = stream.value(QStringLiteral("index")).toInt(-1);
            track.codec = stream.value(QStringLiteral("codec_name")).toString();
            track.width = stream.value(QStringLiteral("width")).toInt();
            track.height = stream.value(QStringLiteral("height")).toInt();
            track.title = tags.value(QStringLiteral("title")).toString();
            track.language = tags.value(QStringLiteral("language")).toString();
            m_videoTracks.append(track);
        } else if (type == QStringLiteral("audio")) {
            AudioTrackInfo track;
            track.streamIndex = stream.value(QStringLiteral("index")).toInt(-1);
            track.codec = stream.value(QStringLiteral("codec_name")).toString();
            track.channels = stream.value(QStringLiteral("channels")).toInt();
            track.channelLayout = stream.value(QStringLiteral("channel_layout")).toString();
            track.title = tags.value(QStringLiteral("title")).toString();
            track.language = tags.value(QStringLiteral("language")).toString();
            track.selected = m_audioTracks.isEmpty();
            m_audioTracks.append(track);
        }
    }
    m_audioTrackLevels.fill(minimumAudioLevelDb, m_audioTracks.size());
    clearAudioWaveforms();
    // Both the track list and the duration are known here, which is everything
    // the waveform decode needs to map samples onto the timeline.
    startWaveformAnalysis();
    emit audioTrackLevelsChanged();
}

QList<int> AppController::selectedAudioTrackIndices() const
{
    QList<int> result;
    for (qsizetype index = 0; index < m_audioTracks.size(); ++index) {
        if (m_audioTracks.at(index).selected) {
            result.append(static_cast<int>(index));
        }
    }
    return result;
}

void AppController::startNextAudioAnalysis()
{
    if (!m_analyzingAudio) {
        return;
    }
    if (m_audioAnalysisQueue.isEmpty()) {
        finishAudioAnalysis();
        return;
    }

    const int trackIndex = m_audioAnalysisQueue.first();
    const int completed = m_audioAnalysisTotal - m_audioAnalysisQueue.size();
    m_audioAnalysisCurrentTrack = trackIndex;
    m_audioAnalysisCurrentOrdinal = completed + 1;
    updateAudioAnalysisProgress(0.0);

    m_audioAnalysisOutput.clear();
    m_audioAnalysisProgressBuffer.clear();
    m_audioAnalysisProcess.start(
        m_ffmpegPath,
        {QStringLiteral("-hide_banner"), QStringLiteral("-nostats"),
         QStringLiteral("-progress"), QStringLiteral("pipe:1"),
         QStringLiteral("-i"), m_selectedFilePath,
         QStringLiteral("-map"), QStringLiteral("0:a:%1").arg(trackIndex),
         QStringLiteral("-af"), QStringLiteral("volumedetect"),
         QStringLiteral("-f"), QStringLiteral("null"),
         QStringLiteral("-")});

    if (!m_audioAnalysisProcess.waitForStarted(5000)) {
        m_audioAnalysisQueue.takeFirst();
        m_audioAnalysisCurrentTrack = -1;
        startNextAudioAnalysis();
    }
}

void AppController::consumeAudioAnalysisProgressOutput()
{
    m_audioAnalysisProgressBuffer += m_audioAnalysisProcess.readAllStandardOutput();
    qsizetype newlineIndex = -1;
    while ((newlineIndex = m_audioAnalysisProgressBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_audioAnalysisProgressBuffer.left(newlineIndex).trimmed();
        m_audioAnalysisProgressBuffer.remove(0, newlineIndex + 1);
        if (!line.startsWith("out_time_us=")) {
            continue;
        }
        bool ok = false;
        const qint64 outputTimeUs = line.mid(sizeof("out_time_us=") - 1).toLongLong(&ok);
        if (ok && m_mediaDurationMs > 0) {
            const double progress = static_cast<double>(outputTimeUs)
                / (static_cast<double>(m_mediaDurationMs) * 1000.0);
            updateAudioAnalysisProgress(std::clamp(progress, 0.0, 1.0));
        }
    }
}

void AppController::updateAudioAnalysisProgress(double trackProgress)
{
    if (m_audioAnalysisCurrentTrack < 0) {
        return;
    }
    m_audioAnalysisTrackProgress = std::clamp(trackProgress, 0.0, 1.0);
    if (m_mediaDurationMs > 0) {
        m_audioAnalysisStatus = QStringLiteral("音声トラック %1 を解析中 (%2/%3): %4%")
                                    .arg(m_audioAnalysisCurrentTrack)
                                    .arg(m_audioAnalysisCurrentOrdinal)
                                    .arg(m_audioAnalysisTotal)
                                    .arg(m_audioAnalysisTrackProgress * 100.0, 0, 'f', 1);
    } else {
        m_audioAnalysisStatus = QStringLiteral("音声トラック %1 を解析中 (%2/%3)…")
                                    .arg(m_audioAnalysisCurrentTrack)
                                    .arg(m_audioAnalysisCurrentOrdinal)
                                    .arg(m_audioAnalysisTotal);
    }
    emit audioAnalysisChanged();
}

void AppController::finishAudioAnalysis()
{
    if (!m_analyzingAudio) {
        return;
    }

    const double targetPerTrackDb = m_audioAnalysisTargetDb
        - 10.0 * std::log10(static_cast<double>(std::max(1, m_audioAnalysisSuccessCount)));
    if (m_audioAnalysisSuccessCount > 0) {
        for (AudioTrackInfo &track : m_audioTracks) {
            if (track.selected && track.hasMeasurement) {
                track.recommendedGainDb = std::clamp(targetPerTrackDb - track.measuredMeanDb,
                                                     minimumAudioGainDb,
                                                     maximumAudioGainDb);
                track.hasRecommendation = true;
                track.gainDb = track.recommendedGainDb;
            }
        }
    }

    m_analyzingAudio = false;
    m_audioAnalysisCurrentTrack = -1;
    m_audioAnalysisTrackProgress = 0.0;
    if (m_audioAnalysisSuccessCount == m_audioAnalysisTotal) {
        m_audioAnalysisStatus = QStringLiteral("自動調整が完了しました（ミックス目標: %1 dBFS）。")
                                    .arg(m_audioAnalysisTargetDb, 0, 'f', 1);
    } else if (m_audioAnalysisSuccessCount > 0) {
        m_audioAnalysisStatus = QStringLiteral("%1/%2 トラックを自動調整しました。")
                                    .arg(m_audioAnalysisSuccessCount)
                                    .arg(m_audioAnalysisTotal);
    } else {
        m_audioAnalysisStatus = QStringLiteral("音量を解析できませんでした。");
    }
    m_audioTrackModel->notifyAllTracksChanged({AudioTrackModel::GainDbRole,
                                               AudioTrackModel::HasMeasurementRole,
                                               AudioTrackModel::MeanVolumeDbRole,
                                               AudioTrackModel::HasRecommendationRole,
                                               AudioTrackModel::RecommendedGainDbRole});
    emit audioAnalysisChanged();
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
    const int outputAudioBitrateKbps = selectedAudioTrackIndices().isEmpty()
        ? 0
        : audioBitrateKbps;
    const int videoBitrateKbps = totalBitrateKbps - outputAudioBitrateKbps;

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
            const QString cacheName = QStringLiteral("%1_%2M_%3.mkv")
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

    QStringList arguments {
        QStringLiteral("-y"),
        QStringLiteral("-i"), m_selectedFilePath,
        QStringLiteral("-ss"), formatTime(startMs),
        QStringLiteral("-t"), formatTime(endMs - startMs),
        QStringLiteral("-map"), QStringLiteral("0:v:%1").arg(m_selectedVideoTrack)
    };
    const QList<int> audioTracks = selectedAudioTrackIndices();
    for (const int trackIndex : audioTracks) {
        arguments << QStringLiteral("-map") << QStringLiteral("0:a:%1").arg(trackIndex);
    }
    arguments << QStringLiteral("-c") << QStringLiteral("copy")
        << QStringLiteral("-avoid_negative_ts") << QStringLiteral("make_zero")
        << QStringLiteral("-progress") << QStringLiteral("pipe:1")
        << QStringLiteral("-nostats")
        << m_cacheFilePath;
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
        const bool cacheInput = !m_cacheFilePath.isEmpty()
            && m_encodingInputPath == m_cacheFilePath;
        arguments << QStringLiteral("-map")
                  << QStringLiteral("0:v:%1").arg(cacheInput ? 0 : m_selectedVideoTrack);

        const QList<int> audioTracks = selectedAudioTrackIndices();
        if (audioTracks.size() == 1) {
            const int sourceAudioIndex = cacheInput ? 0 : audioTracks.first();
            const double gainDb = m_audioTracks.at(audioTracks.first()).gainDb;
            arguments << QStringLiteral("-map")
                      << QStringLiteral("0:a:%1").arg(sourceAudioIndex)
                      << QStringLiteral("-af:a:0")
                      << QStringLiteral("volume=%1dB,alimiter=limit=0.95:level=false:latency=true")
                             .arg(gainDb, 0, 'f', 2);
        } else if (audioTracks.size() > 1) {
            arguments << QStringLiteral("-filter_complex") << audioFilterGraph(cacheInput)
                      << QStringLiteral("-map") << QStringLiteral("[audio_mix]");
        }

        arguments << QStringLiteral("-c:v") << encoder;
        if (encoder == QStringLiteral("libx264")) {
            arguments << QStringLiteral("-preset") << QStringLiteral("medium");
        }
        arguments << QStringLiteral("-b:v") << QStringLiteral("%1k").arg(videoBitrateKbps)
                  << QStringLiteral("-maxrate") << QStringLiteral("%1k").arg(videoBitrateKbps + 5)
                  << QStringLiteral("-bufsize") << QStringLiteral("%1k").arg(videoBitrateKbps * 2)
                  << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p");
        if (!audioTracks.isEmpty()) {
            arguments << QStringLiteral("-c:a") << QStringLiteral("aac")
                      << QStringLiteral("-b:a") << QStringLiteral("%1k").arg(audioBitrateKbps);
        } else {
            arguments << QStringLiteral("-an");
        }
        arguments << QStringLiteral("-movflags") << QStringLiteral("+faststart")
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

QString AppController::audioFilterGraph(bool cacheInput) const
{
    const QList<int> audioTracks = selectedAudioTrackIndices();
    QStringList filters;
    QString mixInputs;
    for (qsizetype position = 0; position < audioTracks.size(); ++position) {
        const int selectedIndex = audioTracks.at(position);
        const int sourceIndex = cacheInput ? static_cast<int>(position) : selectedIndex;
        const double gainDb = m_audioTracks.at(selectedIndex).gainDb;
        const QString label = QStringLiteral("audio_%1").arg(position);
        filters.append(QStringLiteral("[0:a:%1]volume=%2dB[%3]")
                           .arg(sourceIndex)
                           .arg(gainDb, 0, 'f', 2)
                           .arg(label));
        mixInputs += QStringLiteral("[%1]").arg(label);
    }
    filters.append(QStringLiteral("%1amix=inputs=%2:duration=longest:dropout_transition=0:normalize=0,alimiter=limit=0.95:level=false:latency=true[audio_mix]")
                       .arg(mixInputs)
                       .arg(audioTracks.size()));
    return filters.join(QLatin1Char(';'));
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
        setStatusText(QStringLiteral("GPU を利用できないため CPU でエンコード中: 0.0%"));
    } else {
        setStatusText(QStringLiteral("エンコード中 (%1): 0.0%").arg(m_activeEncoderLabel));
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
                    setStatusText(QStringLiteral("GPU を利用できないため CPU でエンコード中: %1%")
                                      .arg(m_progress * 100.0, 0, 'f', 1));
                } else {
                    setStatusText(QStringLiteral("エンコード中 (%1): %2%")
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
