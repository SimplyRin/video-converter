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

public:
    explicit AudioLevelMeter(QObject *parent = nullptr);

    [[nodiscard]] double levelDb() const;
    [[nodiscard]] double gainDb() const;
    void setGainDb(double gainDb);

    Q_INVOKABLE void reset();

signals:
    void levelDbChanged();
    void gainDbChanged();

private:
    void processBuffer(const QAudioBuffer &buffer);

    double m_levelDb = -60.0;
    double m_gainDb = 0.0;
};
