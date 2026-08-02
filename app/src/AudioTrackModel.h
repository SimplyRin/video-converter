// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>

struct AudioTrackInfo {
    int streamIndex = -1;
    QString codec;
    QString title;
    QString language;
    QString channelLayout;
    int channels = 0;
    bool selected = false;
    double gainDb = 0.0;
    double measuredMeanDb = 0.0;
    bool hasMeasurement = false;
    double recommendedGainDb = 0.0;
    bool hasRecommendation = false;
};

// Read-only adapter over AppController's audio track list. Views bind to this
// instead of a QVariantList so per-track state changes arrive as dataChanged()
// on the affected row and the delegates (which own the preview MediaPlayers)
// stay alive instead of being torn down and rebuilt on every change.
class AudioTrackModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectedCountChanged)

public:
    enum Role {
        TrackIndexRole = Qt::UserRole + 1,
        StreamIndexRole,
        LabelRole,
        SelectedRole,
        GainDbRole,
        HasMeasurementRole,
        MeanVolumeDbRole,
        HasRecommendationRole,
        RecommendedGainDbRole,
    };

    explicit AudioTrackModel(const QList<AudioTrackInfo> *tracks, QObject *parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] int count() const;
    [[nodiscard]] int selectedCount() const;

    // AppController mutates the backing list in place and then calls one of
    // these so attached views update without recreating their delegates.
    void notifyReset();
    void notifyTrackChanged(int row, const QList<int> &roles = {});
    void notifyAllTracksChanged(const QList<int> &roles = {});

signals:
    void countChanged();
    void selectedCountChanged();

private:
    const QList<AudioTrackInfo> *m_tracks;
};
