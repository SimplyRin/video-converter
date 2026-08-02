// SPDX-License-Identifier: GPL-3.0-or-later

#include "AudioLevelMeter.h"

#include <QAudioBuffer>
#include <QAudioFormat>
#include <QtGlobal>

#include <algorithm>
#include <cmath>

namespace {
constexpr double minimumLevelDb = -60.0;
constexpr double maximumLevelDb = 0.0;
}

AudioLevelMeter::AudioLevelMeter(QObject *parent)
    : QAudioBufferOutput(parent)
{
    connect(this, &QAudioBufferOutput::audioBufferReceived,
            this, &AudioLevelMeter::processBuffer);
}

double AudioLevelMeter::levelDb() const
{
    return m_levelDb;
}

double AudioLevelMeter::gainDb() const
{
    return m_gainDb;
}

void AudioLevelMeter::setGainDb(double gainDb)
{
    if (!std::isfinite(gainDb) || qFuzzyCompare(m_gainDb, gainDb)) {
        return;
    }
    m_gainDb = gainDb;
    emit gainDbChanged();
}

bool AudioLevelMeter::receivingBuffers() const
{
    return m_receivingBuffers;
}

void AudioLevelMeter::reset()
{
    if (qFuzzyCompare(m_levelDb, minimumLevelDb)) {
        return;
    }
    m_levelDb = minimumLevelDb;
    emit levelDbChanged();
}

void AudioLevelMeter::processBuffer(const QAudioBuffer &buffer)
{
    if (!m_receivingBuffers) {
        m_receivingBuffers = true;
        emit receivingBuffersChanged();
    }

    if (!buffer.isValid() || buffer.sampleCount() <= 0) {
        reset();
        return;
    }

    const QAudioFormat format = buffer.format();
    const int bytesPerSample = format.bytesPerSample();
    if (bytesPerSample <= 0) {
        reset();
        return;
    }

    const auto *samples = buffer.constData<quint8>();
    double squareSum = 0.0;
    for (qsizetype index = 0; index < buffer.sampleCount(); ++index) {
        const float normalized = format.normalizedSampleValue(samples + index * bytesPerSample);
        squareSum += static_cast<double>(normalized) * static_cast<double>(normalized);
    }

    const double meanSquare = squareSum / static_cast<double>(buffer.sampleCount());
    const double measuredDb = meanSquare > 0.0
        ? 10.0 * std::log10(meanSquare) + m_gainDb
        : minimumLevelDb;
    const double adjustedDb = std::clamp(measuredDb, minimumLevelDb, maximumLevelDb);
    if (std::abs(adjustedDb - m_levelDb) < 0.1) {
        return;
    }
    m_levelDb = adjustedDb;
    emit levelDbChanged();
}
