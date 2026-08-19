; Building this produces an UNSIGNED installer, which Windows SmartScreen warns
; about ("Windows protected your PC"). That warning is about the missing
; signature, not about anything in this script — see ../SETUP.md for what it
; takes to remove it. The version and publisher metadata below is filled in
; properly because SmartScreen and antivirus heuristics both weigh it, and
; because a blank publisher field is itself a red flag.

#define MyAppName "Planner"
; CI overrides this with the git tag via `iscc /DMyAppVersion=x.y.z`; the
; fallback only covers local builds. The in-app updater compares this version
; against the latest GitHub release, so a release built with the fallback
; would never be offered as an update.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.1"
#endif
#define MyAppPublisher "Vintazk"
#define MyAppURL "https://vintazk.com"
#define MyAppExeName "planner.exe"

[Setup]
AppId={{D536EA10-B9D2-48C6-9F16-B4880784D359}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
; Shown in the file's Properties -> Details tab, and read by SmartScreen.
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
VersionInfoCopyright=Copyright (C) Vintazk
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=PlannerSetup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

; Uncomment both lines once you have a code signing certificate installed, and
; define the "signtool" entry in Inno Setup under Tools -> Configure Sign Tools.
; This is the only thing that actually removes the SmartScreen warning.
;SignTool=signtool
;SignedUninstaller=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Registry]
Root: HKA; Subkey: "Software\Classes\planner"; ValueType: string; ValueData: "URL:Planner"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\planner"; ValueName: "URL Protocol"; ValueType: string; ValueData: ""
Root: HKA; Subkey: "Software\Classes\planner\DefaultIcon"; ValueType: string; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\planner\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
; No skipifsilent: the in-app updater runs this installer with /SILENT, and
; the relaunch here is what brings the app back after it was closed for the
; update.
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall
