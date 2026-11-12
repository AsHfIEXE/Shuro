; Shuro 2.6.2 Windows installer
; Paths are relative to this script's folder (installer\), so the repo root
; is one level up.

[Setup]
AppName=Shuro
AppVersion=2.6.2
AppVerName=Shuro 2.6.2
AppPublisher=AsHfIEXE
AppPublisherURL=https://github.com/AsHfIEXE/Shuro
AppUpdatesURL=https://github.com/AsHfIEXE/Shuro/releases
AppSupportURL=https://github.com/AsHfIEXE/Shuro/issues
AppComments=Your music, everywhere — a Navidrome / OpenSubsonic client for desktop.
DefaultDirName={autopf}\Shuro
DefaultGroupName=Shuro
UninstallDisplayName=Shuro 2.6.2
UninstallDisplayIcon={app}\shuro.exe
OutputDir=C:\Users\user\Desktop
OutputBaseFilename=Shuro-v2.6.2-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
WizardImageStretch=yes
WizardImageFile=wizard_big.bmp
WizardSmallImageFile=wizard_small.bmp
SetupIconFile=..\windows\runner\resources\app_icon.ico
; Belt and braces alongside the deterministic kill in [Code]: the Restart
; Manager offers to close anything still holding the files (never fires for
; Shuro itself — the kill below already ran), and never re-runs it at login.
CloseApplications=yes
RestartApplications=no

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Shuro"; Filename: "{app}\shuro.exe"
Name: "{autodesktop}\Shuro"; Filename: "{app}\shuro.exe"

[Run]
Filename: "{app}\shuro.exe"; Description: "Launch Shuro"; Flags: nowait postinstall skipifsilent

[Messages]
SelectDirDesc=Where should Shuro be installed?
SelectDirLabel3=Setup will install Shuro into the following folder.
SelectDirBrowseLabel=To continue, click Next. If you would like a different folder, click Browse.
ReadyLabel1=Setup is ready. If Shuro is currently running — even minimized to the tray — it will be closed first, so nothing locks the files.
ReadyLabel2b=Setup is ready. If Shuro is currently running — even minimized to the tray — it will be closed first, so nothing locks the files.

[Code]
// Shuro lives in the tray when its window is closed, so a polite WM_CLOSE
// never ends the process and a running copy keeps shuro.exe locked — which
// is exactly why installs used to fail with "files in use". Force-stop every
// running instance (and its child processes) before Setup touches anything.
// taskkill exits 128 when no such process exists, which is success here.
// The dead tray icon, if any, disappears the first time the mouse passes it.
procedure StopShuro();
var
  ResultCode: Integer;
  Attempts: Integer;
  TempFile: String;
  Lines: TArrayOfString;
begin
  for Attempts := 1 to 3 do
  begin
    Exec(ExpandConstant('{cmd}'), '/C taskkill /F /T /IM shuro.exe',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(400); // let Windows release the file locks before copying over them
    // tasklist prints "INFO: no tasks are running..." when nothing matches.
    TempFile := ExpandConstant('{tmp}\shuro_running.txt');
    Exec(ExpandConstant('{cmd}'),
         '/C tasklist /FI "IMAGENAME eq shuro.exe" /NH > "' + TempFile + '"',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if LoadStringsFromFile(TempFile, Lines) then
      if (GetArrayLength(Lines) = 0) or (Pos('INFO:', Lines[0]) > 0) then
        Break; // no shuro.exe left, the locks are released
  end;
end;

function ShuroStillRunning(): Boolean;
var
  TempFile: String;
  Lines: TArrayOfString;
  ResultCode: Integer;
begin
  Result := False;
  TempFile := ExpandConstant('{tmp}\shuro_running.txt');
  Exec(ExpandConstant('{cmd}'),
       '/C tasklist /FI "IMAGENAME eq shuro.exe" /NH > "' + TempFile + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if LoadStringsFromFile(TempFile, Lines) then
    Result := (GetArrayLength(Lines) > 0) and (Pos('INFO:', Lines[0]) = 0);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  StopShuro();
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  StopShuro(); // again — in case Shuro was launched while the wizard was open
  // Honest failure instead of a cryptic "files in use" halfway through
  // writing files. Setup itself runs elevated (it installs to Program
  // Files), so this only trips if Shuro was started as administrator from a
  // DIFFERENT, higher-trust context or is protected by security software.
  if ShuroStillRunning() then
    Result := 'Shuro is still running and could not be closed.' #13#10 #13#10 +
              'Close it — including the tray icon — then run Setup again.';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    StopShuro(); // uninstall needs the locks released too
end;
