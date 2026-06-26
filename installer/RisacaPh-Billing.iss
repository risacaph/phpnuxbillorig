; ---------------------------------------------------------------------------
; RisacaPh-Billing - Windows installer (Inno Setup 6)
;
; Compiles to: Output\RisacaPh-Billing-Setup-<version>.exe
;
; This is a bootstrapper installer: it bundles ..\windows-install.ps1 and runs
; it elevated during setup. That script installs XAMPP (Apache + MariaDB + PHP),
; deploys the app into htdocs, creates the database, writes config.php and
; registers the billing cron Scheduled Tasks.
;
; Build:  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\RisacaPh-Billing.iss
; (or let the "Build Windows Installer" GitHub Actions workflow build it for you)
; ---------------------------------------------------------------------------

#define MyAppName "RisacaPh-Billing"
#define MyAppVersion "2026.6.26"
#define MyAppPublisher "RisacaPh"
#define MyAppURL "https://github.com/risacaph/phpnuxbillorig"

[Setup]
AppId={{A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=RisacaPh-Billing-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
LicenseFile=..\LICENSE
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; The installer ships the provisioning script and runs it during setup.
Source: "..\windows-install.ps1"; DestDir: "{app}"; Flags: ignoreversion

[INI]
Filename: "{app}\RisacaPh-Billing Admin.url"; Section: "InternetShortcut"; \
    Key: "URL"; String: "http://localhost/risacaph-billing/admin"

[Icons]
Name: "{group}\RisacaPh-Billing Admin"; Filename: "{app}\RisacaPh-Billing Admin.url"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
; Bootstrap: run the PowerShell provisioning script (XAMPP, DB, cron, app).
; The console stays visible so the user can watch progress on a fresh install.
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows-install.ps1"""; \
    StatusMsg: "Installing RisacaPh-Billing - XAMPP, database and cron (this can take several minutes)..."; \
    Flags: runascurrentuser waituntilterminated

[Messages]
FinishedLabel=RisacaPh-Billing has been installed. Open http://localhost/risacaph-billing/admin and sign in with admin / admin, then change the password immediately.
