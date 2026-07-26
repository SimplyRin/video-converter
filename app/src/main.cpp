// SPDX-License-Identifier: GPL-3.0-or-later

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#include "AppController.h"

int main(int argc, char *argv[])
{
    QGuiApplication::setApplicationName(QStringLiteral("DiscordVideo"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("DiscordVideo"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("simplyrin.net"));
    QGuiApplication::setOrganizationName(QStringLiteral("SimplyRin"));

    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    AppController controller;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &controller);
    engine.loadFromModule(QStringLiteral("DiscordVideo"), QStringLiteral("Main"));

    if (engine.rootObjects().isEmpty()) {
        return EXIT_FAILURE;
    }

    return app.exec();
}

