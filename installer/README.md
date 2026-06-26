# RisacaPh-Billing — Windows installer

This folder builds a Windows setup executable
(`RisacaPh-Billing-Setup-<version>.exe`) from `RisacaPh-Billing.iss` using
[Inno Setup 6](https://jrsoftware.org/isdl.php).

The installer is a **bootstrapper**: it bundles `../windows-install.ps1` and runs
it during setup. That script installs **XAMPP** (Apache + MariaDB + PHP), deploys
the app into `htdocs`, creates the database, writes `config.php`, and registers
the billing cron Scheduled Tasks. It finishes at `http://localhost/phpnuxbill/admin`
with the default login **admin / admin** (change it immediately).

## Get the `.exe`

- **From a Release** — every pushed tag triggers the *Build Windows Installer*
  GitHub Actions workflow, which compiles the installer and attaches the `.exe`
  to that release.
- **On demand** — open the **Actions** tab → *Build Windows Installer* →
  **Run workflow**; download the `.exe` from the run's **Artifacts**.

## Build it yourself (on Windows)

1. Install [Inno Setup 6](https://jrsoftware.org/isdl.php) (free).
2. Compile, either by opening `RisacaPh-Billing.iss` in the Inno Setup IDE and
   clicking **Build → Compile**, or from a terminal:
   ```
   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\RisacaPh-Billing.iss
   ```
3. The installer is written to
   `installer\Output\RisacaPh-Billing-Setup-<version>.exe`.

> When cutting a release, bump `MyAppVersion` in `RisacaPh-Billing.iss` to match
> `version.json`.
