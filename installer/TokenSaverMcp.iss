; Standalone installer for TokenSaver MCP. It wraps the WiX MSI (src/Installers/TokenSaver.Setup),
; which installs the TokenSaverMCP Windows service. The MSI does the real work; this script runs
; msiexec silently and reports failures. Built by scripts/build-standalone-installer.ps1.
;
; Defines (passed by the build script):
;   MyAppVersion         display version, e.g. 1.0.49-alpha
;   MyAppNumericVersion  four-part numeric version, e.g. 1.0.49.0
;   TokenSaverMsi        absolute path to the built TokenSaver-Setup-<numeric>.msi

#ifndef MyAppVersion
  #error "MyAppVersion must be defined by the build script."
#endif
#ifndef MyAppNumericVersion
  #error "MyAppNumericVersion must be defined by the build script."
#endif
#ifndef TokenSaverMsi
  #error "TokenSaverMsi must be defined by the build script."
#endif

#define MyAppName "TokenSaver MCP"
#define MyPublisher "Richard Sperry"

[Setup]
; Distinct from SimpleModelServer's AppId, so the two installers never upgrade each other.
AppId={{6B1E0C7A-3F2D-4B8E-9A51-7C2D8E4F0A13}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyPublisher}
VersionInfoVersion={#MyAppNumericVersion}
DefaultDirName={autopf}\TokenSaver
DisableProgramGroupPage=yes
DisableDirPage=yes
OutputDir=..\build\dist
OutputBaseFilename=TokenSaverMCP-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
RestartIfNeededByRun=no
; Shown after installation: how to connect an AI client. Path is relative to this script.
InfoAfterFile=TokenSaverMcp-README.txt

[Dirs]
; The MSI's log goes here. The folder is never removed on uninstall, so logs survive.
Name: "{commonappdata}\TokenSaver"; Flags: uninsneveruninstall

[Files]
Source: "{#TokenSaverMsi}"; DestDir: "{app}"; DestName: "TokenSaver-Setup.msi"; Flags: ignoreversion
Source: "TokenSaverMcp-README.txt"; DestDir: "{app}"; DestName: "CONNECT-TO-AI-CLIENT.txt"; Flags: ignoreversion

[Code]
const
  MsiExe = '{sys}\msiexec.exe';

function MsiPath(): String;
begin
  Result := ExpandConstant('{app}\TokenSaver-Setup.msi');
end;

function MsiLogPath(): String;
begin
  Result := ExpandConstant('{commonappdata}\TokenSaver\msi-install.log');
end;

{ Installs or upgrades the MSI. Its UpgradeCode makes msiexec upgrade an existing TokenSaver install. }
procedure InstallMsi();
var
  ResultCode: Integer;
begin
  if not Exec(ExpandConstant(MsiExe),
       '/i "' + MsiPath() + '" /qn /norestart /l*v "' + MsiLogPath() + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  { 3010 means success with a reboot still needed. This installer does not reboot itself. }
  if (ResultCode <> 0) and (ResultCode <> 3010) then
    MsgBox('TokenSaver MCP did not install (msiexec exit code ' + IntToStr(ResultCode) + '). ' +
           'The log is at ' + MsiLogPath() + '.', mbCriticalError, MB_OK);
end;

procedure UninstallMsi();
var
  ResultCode: Integer;
begin
  if not Exec(ExpandConstant(MsiExe),
       '/x "' + MsiPath() + '" /qn /norestart /l*v "' + MsiLogPath() + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  if (ResultCode <> 0) and (ResultCode <> 3010) then
    MsgBox('TokenSaver MCP was not removed (msiexec exit code ' + IntToStr(ResultCode) + '). ' +
           'Remove it from Apps & Features. The log is at ' + MsiLogPath() + '.', mbError, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    InstallMsi();
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    UninstallMsi();
end;
