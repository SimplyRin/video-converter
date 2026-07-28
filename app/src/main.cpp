// SPDX-License-Identifier: GPL-3.0-or-later

#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#include "AppController.h"

int main(int argc, char *argv[])
{
    QApplication::setApplicationName(QStringLiteral("DiscordVideo"));
    QApplication::setApplicationDisplayName(QStringLiteral("DiscordVideo"));
    QApplication::setOrganizationDomain(QStringLiteral("simplyrin.net"));
    QApplication::setOrganizationName(QStringLiteral("SimplyRin"));
    QApplication::setApplicationVersion(QStringLiteral(DISCORDVIDEO_VERSION));

    QApplication app(argc, argv);
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/DiscordVideo.ico")));

    AppController controller;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &controller);
    engine.loadFromModule(QStringLiteral("DiscordVideo"), QStringLiteral("Main"));

    if (engine.rootObjects().isEmpty()) {
        return EXIT_FAILURE;
    }

    return app.exec();
}
