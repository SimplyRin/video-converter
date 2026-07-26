# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.21)

set(DISCORDVIDEO_VERSION "2.0.0" CACHE STRING "DiscordVideo release version")
project(DiscordVideo VERSION "${DISCORDVIDEO_VERSION}" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Multimedia
    Network
    Qml
    Quick
    QuickControls2
    Widgets
)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(discord-video
    src/main.cpp
    src/AppController.cpp
    src/AppController.h
)

qt_add_qml_module(discord-video
    URI DiscordVideo
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/TrimWindow.qml
)

target_link_libraries(discord-video PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Multimedia
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)

set_target_properties(discord-video PROPERTIES
    OUTPUT_NAME "DiscordVideo"
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "DiscordVideo"
    MACOSX_BUNDLE_GUI_IDENTIFIER "net.simplyrin.discordvideo"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    WIN32_EXECUTABLE TRUE
)

include(GNUInstallDirs)
install(TARGETS discord-video
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
