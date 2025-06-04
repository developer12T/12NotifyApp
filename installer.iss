[Setup]
AppName=12Chat
AppVersion=1.0.0
AppPublisher=12Trading
AppPublisherURL=https://www.f-plus.co.th/th/index.php
DefaultDirName={autopf}\12Chat
DefaultGroupName=12Chat
AllowNoIcons=yes
OutputDir=installer_output
OutputBaseFilename=12ChatSetup
SetupIconFile=assets\icon\app_icon.ico
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copy ไฟล์ executable และ rename เป็นชื่อที่ต้องการ
Source: "build\windows\x64\runner\Release\NotiOneTwo.exe"; DestDir: "{app}"; DestName: "12_notify_app.exe"; Flags: ignoreversion
; Copy ไฟล์อื่นๆ ทั้งหมด ยกเว้น .exe หลัก
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "12_notify_app.exe"; Flags: ignoreversion recursesubdirs createallsubdirs
; Copy icon file
Source: "assets\icon\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\12Chat"; Filename: "{app}\12_notify_app.exe"; IconFilename: "{app}\app_icon.ico"
Name: "{commondesktop}\12Chat"; Filename: "{app}\12_notify_app.exe"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\12_notify_app.exe"; Description: "{cm:LaunchProgram,12Chat}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\12Chat"; ValueType: string; ValueName: "DisplayName"; ValueData: "12Chat"
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\12Chat"; ValueType: string; ValueName: "DisplayVersion"; ValueData: "1.0.0"
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\12Chat"; ValueType: string; ValueName: "Publisher"; ValueData: "12Trading"
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\12Chat"; ValueType: string; ValueName: "UninstallString"; ValueData: "{uninstallexe}"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;