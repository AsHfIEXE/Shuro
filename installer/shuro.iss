; Shuro 2.6.2 Windows installer
[Setup]
AppName=Shuro
AppVersion=2.6.2
AppVerName=Shuro 2.6.2
AppPublisher=AsHfIEXE
DefaultDirName={autopf}\Shuro
DefaultGroupName=Shuro
UninstallDisplayIcon={app}\shuro.exe
OutputDir=C:\Users\user\Desktop
OutputBaseFilename=Shuro-v2.6.2-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Shuro"; Filename: "{app}\shuro.exe"
Name: "{autodesktop}\Shuro"; Filename: "{app}\shuro.exe"

[Run]
Filename: "{app}\shuro.exe"; Description: "Launch Shuro"; Flags: nowait postinstall skipifsilent
