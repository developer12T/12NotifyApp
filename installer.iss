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
Source: "build\windows\x64\runner\Debug*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\12Chat"; Filename: "{app}\12_notify_app.exe"; IconFilename: "{app}\app_icon.ico"
Name: "{commondesktop}\12Chat"; Filename: "{app}\12_notify_app.exe"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\12_notify_app.exe"; Description: "{cm:LaunchProgram,12Chat}"; Flags: nowait postinstall skipifsilent

[Registry]
; เพิ่ม uninstall information
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\12Chat"; ValueType: string; ValueName: "DisplayName"; ValueData: "12Chat"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Custom code สำหรับตรวจสอบ .NET Framework หรือ dependencies อื่นๆ
function InitializeSetup(): Boolean;
begin
  Result := True;
end;