// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QAudioBufferOutput>
#include <QtQml/qqmlregistration.h>

class AudioLevelMeter : public QAudioBufferOutput
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(double levelDb READ levelDb NOTIFY levelDbChanged)
    Q_PROPERTY(double gainDb READ gainDb WRITE setGainDb NOTIFY gainDbChanged)
    Q_PROPERTY(bool receivingBuffers READ receivingBuffers NOTIFY receivingBuffersChanged)

public:
    explicit AudioLevelMeter(QObject *parent = nullptr);

    [[nodiscard]] double levelDb() const;
    [[nodiscard]] double gainDb() const;
    void setGainDb(double gainDb);

    // False until the media backend has delivered at least one audio buffer.
    // Backends without QAudioBufferOutput support (for example the macOS
    // AVFoundation backend) never emit audioBufferReceived, so level metering
    // and the waveform stay silent and the UI has to say so.
    [[nodiscard]] bool receivingBuffers() const;

    Q_INVOKABLE void reset();

signals:
    void levelDbChanged();
    void gainDbChanged();
    void receivingBuffersChanged();

private:
    void processBuffer(const QAudioBuffer &buffer);

    double m_levelDb = -60.0;
    double m_gainDb = 0.0;
    bool m_receivingBuffers = false;
};
