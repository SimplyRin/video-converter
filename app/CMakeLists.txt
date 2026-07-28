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

set(DISCORDVIDEO_ICON_ICO "${CMAKE_CURRENT_SOURCE_DIR}/assets/DiscordVideo.ico")
set_source_files_properties("${DISCORDVIDEO_ICON_ICO}" PROPERTIES
    QT_RESOURCE_ALIAS "DiscordVideo.ico"
)
qt_add_resources(discord-video "discordvideo_icons"
    PREFIX "/icons"
    FILES "${DISCORDVIDEO_ICON_ICO}"
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

if(APPLE)
    set(DISCORDVIDEO_ICON_ICNS "${CMAKE_CURRENT_SOURCE_DIR}/assets/DiscordVideo.icns")
    set_source_files_properties("${DISCORDVIDEO_ICON_ICNS}" PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    target_sources(discord-video PRIVATE "${DISCORDVIDEO_ICON_ICNS}")
    set_target_properties(discord-video PROPERTIES
        MACOSX_BUNDLE_ICON_FILE "DiscordVideo.icns"
    )
endif()

if(WIN32)
    enable_language(RC)
    set(DISCORDVIDEO_WINDOWS_ICON "${DISCORDVIDEO_ICON_ICO}")
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/assets/DiscordVideo.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/DiscordVideo.rc"
        @ONLY
    )
    target_sources(discord-video PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/DiscordVideo.rc")

    target_link_libraries(discord-video PRIVATE
        ole32
        shell32
    )

    set_target_properties(discord-video PROPERTIES OUTPUT_NAME "DiscordVideoApp")

    add_executable(discord-video-launcher WIN32
        src/WindowsLauncher.cpp
        "${CMAKE_CURRENT_BINARY_DIR}/DiscordVideo.rc"
    )
    set_target_properties(discord-video-launcher PROPERTIES
        OUTPUT_NAME "DiscordVideo"
    )
    if(MINGW)
        target_link_options(discord-video-launcher PRIVATE
            -static
            -static-libgcc
            -static-libstdc++
        )
    endif()
endif()

include(GNUInstallDirs)
install(TARGETS discord-video
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

if(WIN32)
    install(TARGETS discord-video-launcher
        RUNTIME DESTINATION .
    )
endif()
