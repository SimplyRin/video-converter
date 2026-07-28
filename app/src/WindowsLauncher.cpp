// SPDX-License-Identifier: GPL-3.0-or-later

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace {

constexpr DWORD PathCapacity = 32768;

void showLaunchError(const wchar_t *message)
{
    MessageBoxW(nullptr, message, L"DiscordVideo", MB_OK | MB_ICONERROR);
}

const wchar_t *commandLineArguments()
{
    const wchar_t *cursor = GetCommandLineW();
    if (*cursor == L'\"') {
        ++cursor;
        while (*cursor != L'\0' && *cursor != L'\"') {
            ++cursor;
        }
        if (*cursor == L'\"') {
            ++cursor;
        }
    } else {
        while (*cursor != L'\0' && *cursor != L' ' && *cursor != L'\t') {
            ++cursor;
        }
    }

    while (*cursor == L' ' || *cursor == L'\t') {
        ++cursor;
    }
    return cursor;
}

} // namespace

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int)
{
    wchar_t launcherPath[PathCapacity] {};
    const DWORD launcherLength = GetModuleFileNameW(nullptr, launcherPath, PathCapacity);
    if (launcherLength == 0 || launcherLength >= PathCapacity) {
        showLaunchError(L"DiscordVideoの配置場所を取得できませんでした。");
        return 1;
    }

    wchar_t *lastSeparator = launcherPath + launcherLength;
    while (lastSeparator != launcherPath && *lastSeparator != L'\\' && *lastSeparator != L'/') {
        --lastSeparator;
    }
    if (lastSeparator == launcherPath) {
        showLaunchError(L"DiscordVideoの配置場所が正しくありません。");
        return 1;
    }
    *lastSeparator = L'\0';

    constexpr wchar_t BinSuffix[] = L"\\bin";
    constexpr wchar_t AppSuffix[] = L"\\DiscordVideoApp.exe";
    if (lstrlenW(launcherPath) + lstrlenW(BinSuffix) + lstrlenW(AppSuffix) + 1 >= PathCapacity) {
        showLaunchError(L"DiscordVideoの配置パスが長すぎます。");
        return 1;
    }

    wchar_t binDirectory[PathCapacity] {};
    lstrcpyW(binDirectory, launcherPath);
    lstrcatW(binDirectory, BinSuffix);

    wchar_t applicationPath[PathCapacity] {};
    lstrcpyW(applicationPath, binDirectory);
    lstrcatW(applicationPath, AppSuffix);
    if (GetFileAttributesW(applicationPath) == INVALID_FILE_ATTRIBUTES) {
        showLaunchError(L"bin\\DiscordVideoApp.exeが見つかりません。ZIPをフォルダーごと展開してください。");
        return 1;
    }

    const wchar_t *arguments = commandLineArguments();
    const SIZE_T commandLineLength = lstrlenW(applicationPath) + lstrlenW(arguments) + 5;
    auto *childCommandLine = static_cast<wchar_t *>(
        HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, commandLineLength * sizeof(wchar_t)));
    if (childCommandLine == nullptr) {
        showLaunchError(L"DiscordVideoを起動するためのメモリを確保できませんでした。");
        return 1;
    }

    lstrcpyW(childCommandLine, L"\"");
    lstrcatW(childCommandLine, applicationPath);
    lstrcatW(childCommandLine, L"\"");
    if (*arguments != L'\0') {
        lstrcatW(childCommandLine, L" ");
        lstrcatW(childCommandLine, arguments);
    }

    STARTUPINFOW startupInfo {};
    startupInfo.cb = sizeof(startupInfo);
    PROCESS_INFORMATION processInfo {};
    const BOOL started = CreateProcessW(applicationPath,
                                        childCommandLine,
                                        nullptr,
                                        nullptr,
                                        FALSE,
                                        0,
                                        nullptr,
                                        binDirectory,
                                        &startupInfo,
                                        &processInfo);
    HeapFree(GetProcessHeap(), 0, childCommandLine);

    if (!started) {
        showLaunchError(L"bin\\DiscordVideoApp.exeを起動できませんでした。ファイル構成を確認してください。");
        return 1;
    }

    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);
    return 0;
}
