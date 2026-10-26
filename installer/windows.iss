; PassVault Windows 安装包（Inno Setup 6）
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F1B3C2A-5E7D-4C8B-9A21-3D5AFE7C4DFF}
AppName=PassVault
AppVersion={#AppVersion}
AppPublisher=xichugeek
DefaultDirName={localappdata}\Programs\PassVault
DefaultGroupName=PassVault
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..
OutputBaseFilename=PassVault-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\PassVault.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
#if FileExists(CompilerPath + "Languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PassVault"; Filename: "{app}\PassVault.exe"
Name: "{autodesktop}\PassVault"; Filename: "{app}\PassVault.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\PassVault.exe"; Description: "{cm:LaunchProgram,PassVault}"; Flags: nowait postinstall skipifsilent
