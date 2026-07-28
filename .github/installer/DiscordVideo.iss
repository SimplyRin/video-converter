; SPDX-License-Identifier: GPL-3.0-or-later

#define AppVersion GetEnv("DISCORDVIDEO_INSTALLER_VERSION")
#define BuildNumber GetEnv("DISCORDVIDEO_INSTALLER_BUILD_NUMBER")
#define PackageSource GetEnv("DISCORDVIDEO_INSTALLER_PACKAGE_SOURCE")
#define InstallerOutput GetEnv("DISCORDVIDEO_INSTALLER_OUTPUT")

[Setup]
AppId={{D046999A-1929-443F-9DB2-25E0A52024A4}
AppName=DiscordVideo
AppVersion={#AppVersion}+{#BuildNumber}
AppPublisher=SimplyRin
AppPublisherURL=https://github.com/SimplyRin/video-converter
AppSupportURL=https://github.com/SimplyRin/video-converter/issues
AppUpdatesURL=https://github.com/SimplyRin/video-converter/releases
DefaultDirName={autopf}\DiscordVideo
DefaultGroupName=DiscordVideo
DisableProgramGroupPage=yes
LicenseFile={#PackageSource}\LICENSE.md
OutputDir={#InstallerOutput}
OutputBaseFilename=Windows-x64-Setup_v{#AppVersion}+{#BuildNumber}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern dynamic
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupLogging=yes
UninstallDisplayIcon={app}\DiscordVideo.exe
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PackageSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: filesandordirs; Name: "{app}\bin"

[Icons]
Name: "{autoprograms}\DiscordVideo"; Filename: "{app}\DiscordVideo.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\DiscordVideo"; Filename: "{app}\DiscordVideo.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\DiscordVideo.exe"; Description: "{cm:LaunchProgram,DiscordVideo}"; Flags: nowait postinstall skipifsilent
