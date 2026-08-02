// SPDX-License-Identifier: GPL-3.0-or-later

#include "AudioTrackModel.h"

AudioTrackModel::AudioTrackModel(const QList<AudioTrackInfo> *tracks, QObject *parent)
    : QAbstractListModel(parent)
    , m_tracks(tracks)
{
}

int AudioTrackModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_tracks->size());
}

QVariant AudioTrackModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_tracks->size()) {
        return {};
    }
    const AudioTrackInfo &track = m_tracks->at(index.row());
    switch (role) {
    case TrackIndexRole:
        return index.row();
    case StreamIndexRole:
        return track.streamIndex;
    case LabelRole: {
        QStringList details;
        if (!track.codec.isEmpty()) {
            details.append(track.codec.toUpper());
        }
        if (!track.channelLayout.isEmpty()) {
            details.append(track.channelLayout);
        } else if (track.channels > 0) {
            details.append(QStringLiteral("%1 ch").arg(track.channels));
        }
        if (!track.language.isEmpty() && track.language != QStringLiteral("und")) {
            details.append(track.language);
        }
        if (!track.title.isEmpty()) {
            details.append(track.title);
        }
        return QStringLiteral("%1: %2")
            .arg(index.row())
            .arg(details.isEmpty() ? QStringLiteral("音声トラック")
                                   : details.join(QStringLiteral(" · ")));
    }
    case SelectedRole:
        return track.selected;
    case GainDbRole:
        return track.gainDb;
    case HasMeasurementRole:
        return track.hasMeasurement;
    case MeanVolumeDbRole:
        return track.measuredMeanDb;
    case HasRecommendationRole:
        return track.hasRecommendation;
    case RecommendedGainDbRole:
        return track.recommendedGainDb;
    default:
        return {};
    }
}

QHash<int, QByteArray> AudioTrackModel::roleNames() const
{
    return {
        {TrackIndexRole, QByteArrayLiteral("trackIndex")},
        {StreamIndexRole, QByteArrayLiteral("streamIndex")},
        {LabelRole, QByteArrayLiteral("label")},
        {SelectedRole, QByteArrayLiteral("selected")},
        {GainDbRole, QByteArrayLiteral("gainDb")},
        {HasMeasurementRole, QByteArrayLiteral("hasMeasurement")},
        {MeanVolumeDbRole, QByteArrayLiteral("meanVolumeDb")},
        {HasRecommendationRole, QByteArrayLiteral("hasRecommendation")},
        {RecommendedGainDbRole, QByteArrayLiteral("recommendedGainDb")},
    };
}

int AudioTrackModel::count() const
{
    return static_cast<int>(m_tracks->size());
}

int AudioTrackModel::selectedCount() const
{
    int result = 0;
    for (const AudioTrackInfo &track : *m_tracks) {
        if (track.selected) {
            ++result;
        }
    }
    return result;
}

void AudioTrackModel::notifyReset()
{
    beginResetModel();
    endResetModel();
    emit countChanged();
    emit selectedCountChanged();
}

void AudioTrackModel::notifyTrackChanged(int row, const QList<int> &roles)
{
    if (row < 0 || row >= m_tracks->size()) {
        return;
    }
    const QModelIndex modelIndex = index(row);
    emit dataChanged(modelIndex, modelIndex, QList<int>(roles));
    if (roles.isEmpty() || roles.contains(SelectedRole)) {
        emit selectedCountChanged();
    }
}

void AudioTrackModel::notifyAllTracksChanged(const QList<int> &roles)
{
    if (m_tracks->isEmpty()) {
        return;
    }
    emit dataChanged(index(0), index(static_cast<int>(m_tracks->size()) - 1),
                     QList<int>(roles));
    if (roles.isEmpty() || roles.contains(SelectedRole)) {
        emit selectedCountChanged();
    }
}
