<#
.SYNOPSIS
    RisacaPh-Billing Windows installer (XAMPP-based).

.DESCRIPTION
    Installs RisacaPh-Billing on Windows using XAMPP (Apache + MariaDB + PHP 8.2).
    It deploys the app into XAMPP's htdocs, creates the database and a dedicated
    DB user, writes config.php, registers Scheduled Tasks for the billing cron,
    and finishes with a working admin login (admin / admin).

    Run from an ELEVATED (Administrator) PowerShell prompt:
        powershell -ExecutionPolicy Bypass -File .\windows-install.ps1

    Override defaults with parameters, e.g.:
        .\windows-install.ps1 -AppName billing -DbPass 'S3cret!'

.NOTES
    Not testable on non-Windows; smoke-test on a real Windows host. If XAMPP is
    already installed, pass -XamppDir to point at it and the download is skipped.
#>

#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$XamppDir    = 'C:\xampp',
    [string]$XamppUrl    = 'https://sourceforge.net/projects/xampp/files/XAMPP%20Windows/8.2.12/xampp-windows-x64-8.2.12-0-VS16-installer.exe/download',
    [string]$AppName     = 'risacaph-billing',
    [string]$RepoZipUrl  = 'https://github.com/risacaph/phpnuxbillorig/archive/refs/heads/master.zip',
    [string]$DbName      = 'risacaph_billing',
    [string]$DbUser      = 'risacaph_billing',
    [string]$DbPass      = '',          # generated if empty
    [int]   $CronMinutes = 5
)

$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host "==> $m"   -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!] $m"  -ForegroundColor Yellow }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Die "Run this script from an elevated (Administrator) PowerShell."
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ([string]::IsNullOrWhiteSpace($DbPass)) {
    $DbPass = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
}

$php    = Join-Path $XamppDir 'php\php.exe'
$mysql  = Join-Path $XamppDir 'mysql\bin\mysql.exe'
$htdocs = Join-Path $XamppDir 'htdocs'
$appDir = Join-Path $htdocs $AppName

Info "XAMPP dir : $XamppDir"
Info "App dir   : $appDir"
Info "Source    : $RepoZipUrl"
Info "Database  : $DbName (user $DbUser)"

# ---------------------------------------------------------------------------
# Ensure XAMPP
# ---------------------------------------------------------------------------
if (-not (Test-Path $php)) {
    Info "XAMPP not found at $XamppDir - downloading installer (this is large)..."
    $inst = Join-Path $env:TEMP 'xampp-installer.exe'
    Invoke-WebRequest -Uri $XamppUrl -OutFile $inst -UseBasicParsing
    Info "Running XAMPP unattended install..."
    Start-Process -FilePath $inst -Wait -ArgumentList @(
        '--mode', 'unattended', '--unattendedmodeui', 'none',
        '--prefix', $XamppDir, '--launchapps', '0'
    )
    if (-not (Test-Path $php)) {
        Die "XAMPP install did not produce $php. Install XAMPP manually, then re-run with -XamppDir."
    }
    Ok "XAMPP installed at $XamppDir"
} else {
    Ok "Using existing XAMPP at $XamppDir"
}

# ---------------------------------------------------------------------------
# Install + start Apache and MySQL services
# ---------------------------------------------------------------------------
Info "Installing Apache & MySQL services..."
foreach ($bat in @('apache_installservice.bat', 'mysql_installservice.bat')) {
    $p = Join-Path $XamppDir $bat
    if (Test-Path $p) {
        Start-Process -FilePath $p -WorkingDirectory $XamppDir -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
    }
}
foreach ($svc in @('mysql', 'Apache2.4')) {
    try { Start-Service $svc -ErrorAction Stop; Ok "Started service $svc" }
    catch { Warn "Could not start service '$svc' (it may already be running, or port 80/3306 is in use)" }
}

Info "Waiting for MySQL..."
$mysqlReady = $false
for ($i = 0; $i -lt 30; $i++) {
    & $mysql -u root -e "SELECT 1;" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $mysqlReady = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $mysqlReady) { Die "MySQL is not responding. Start XAMPP MySQL manually and re-run." }
Ok "MySQL is up"

# ---------------------------------------------------------------------------
# Deploy the application
# ---------------------------------------------------------------------------
if (Test-Path $appDir) { Die "$appDir already exists - remove it or pass a different -AppName." }

Info "Downloading RisacaPh-Billing..."
$zip  = Join-Path $env:TEMP 'phpnuxbill.zip'
$xdir = Join-Path $env:TEMP 'phpnuxbill-extract'
Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zip -UseBasicParsing
if (Test-Path $xdir) { Remove-Item $xdir -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $xdir -Force
$src = Get-ChildItem $xdir -Directory | Select-Object -First 1
if (-not $src) { Die "Could not find extracted source in $xdir" }
Move-Item $src.FullName $appDir
Ok "Deployed to $appDir"

# Page content lives in pages_template until first install
$pagesTpl = Join-Path $appDir 'pages_template'
$pages    = Join-Path $appDir 'pages'
if ((Test-Path $pagesTpl) -and -not (Test-Path $pages)) {
    Copy-Item $pagesTpl $pages -Recurse
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
Info "Creating database and user..."
$createSql = "CREATE DATABASE IF NOT EXISTS $DbName CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; " +
             "CREATE USER IF NOT EXISTS '$DbUser'@'localhost' IDENTIFIED BY '$DbPass'; " +
             "GRANT ALL PRIVILEGES ON $DbName.* TO '$DbUser'@'localhost'; FLUSH PRIVILEGES;"
& $mysql -u root -e $createSql
if ($LASTEXITCODE -ne 0) { Die "Failed to create database/user." }

Info "Importing schema..."
$schema = Join-Path $appDir 'install\phpnuxbill.sql'
Get-Content $schema -Raw | & $mysql -u root $DbName
if ($LASTEXITCODE -ne 0) { Die "Failed to import phpnuxbill.sql." }
Ok "Database ready"

# ---------------------------------------------------------------------------
# config.php  (PHP $-vars are backtick-escaped; PowerShell vars interpolate)
# ---------------------------------------------------------------------------
Info "Writing config.php..."
$configBody = @"
<?php
`$protocol = (!empty(`$_SERVER['HTTPS']) && `$_SERVER['HTTPS'] !== 'off' || (isset(`$_SERVER['SERVER_PORT']) && `$_SERVER['SERVER_PORT'] == 443)) ? "https://" : "http://";
`$host = isset(`$_SERVER['HTTP_HOST']) ? `$_SERVER['HTTP_HOST'] : (isset(`$_SERVER['SERVER_NAME']) ? `$_SERVER['SERVER_NAME'] : 'localhost');
`$baseDir = rtrim(dirname(`$_SERVER['SCRIPT_NAME']), '/\\');
define('APP_URL', `$protocol . `$host . `$baseDir);

`$_app_stage = 'Live';

`$db_host = 'localhost';
`$db_port = '';
`$db_user = '$DbUser';
`$db_pass = '$DbPass';
`$db_name = '$DbName';

error_reporting(E_ERROR);
ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
"@
Set-Content -Path (Join-Path $appDir 'config.php') -Value $configBody -Encoding UTF8

# Activate the shipped firewall/rewrite rules (XAMPP htdocs is AllowOverride All)
$fw = Join-Path $appDir '.htaccess_firewall'
$ht = Join-Path $appDir '.htaccess'
if ((Test-Path $fw) -and -not (Test-Path $ht)) { Copy-Item $fw $ht }

# Lock down the web installer
Remove-Item (Join-Path $appDir 'install') -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Scheduled tasks (the billing cron)
# ---------------------------------------------------------------------------
Info "Registering scheduled tasks..."
try {
    $cronAction = New-ScheduledTaskAction -Execute $php -Argument "`"$appDir\system\cron.php`""
    $cronTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $CronMinutes)
    Register-ScheduledTask -TaskName 'RisacaPh-Billing Cron' -Action $cronAction -Trigger $cronTrigger `
        -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

    $remAction = New-ScheduledTaskAction -Execute $php -Argument "`"$appDir\system\cron_reminder.php`""
    $remTrigger = New-ScheduledTaskTrigger -Daily -At 8am
    Register-ScheduledTask -TaskName 'RisacaPh-Billing Reminder' -Action $remAction -Trigger $remTrigger `
        -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Ok "Scheduled tasks 'RisacaPh-Billing Cron' (every $CronMinutes min) and 'RisacaPh-Billing Reminder' (daily 08:00)"
} catch {
    Warn "Could not register scheduled tasks: $($_.Exception.Message)"
    Warn "Create them manually to run: $php <path>\system\cron.php"
}

# ---------------------------------------------------------------------------
# Credentials + summary
# ---------------------------------------------------------------------------
$creds = @"
RisacaPh-Billing installation
=======================
Admin login : admin / admin   (change this immediately)
URL         : http://localhost/$AppName/admin
Database    : $DbName
DB user     : $DbUser
DB password : $DbPass
App folder  : $appDir
"@
Set-Content -Path (Join-Path $appDir 'INSTALL-CREDENTIALS.txt') -Value $creds -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " RisacaPh-Billing is installed" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Admin portal : http://localhost/$AppName/admin"
Write-Host "  Login        : admin / admin   (change immediately)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  DB name      : $DbName"
Write-Host "  DB user      : $DbUser"
Write-Host "  DB password  : $DbPass"
Write-Host ""
Write-Host "  Credentials saved to $appDir\INSTALL-CREDENTIALS.txt"
Write-Host ""
Warn "If the page does not load, make sure XAMPP Apache started (port 80 free)."
Warn "First steps: log in, change the admin password, then add your router under Network."
