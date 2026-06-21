<?php

/**
 * Installer lockdown.
 *
 * Once the application is installed, a non-empty config.php exists at the web
 * root. From that point the installer must refuse to run, otherwise anyone who
 * can reach /install/ could overwrite config.php (pointing the app at their own
 * database), re-import the SQL seed and reset the admin account to admin/admin.
 *
 * This is a server-agnostic guard (works on Apache and nginx) and is included
 * at the very top of every installer entry point. It is intentionally NOT
 * applied to step5.php, which legitimately runs after config.php is created.
 */

$installed_config = __DIR__ . DIRECTORY_SEPARATOR . '..' . DIRECTORY_SEPARATOR . 'config.php';
if (file_exists($installed_config) && filesize($installed_config) > 0) {
    header('HTTP/1.1 403 Forbidden', true, 403);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Installer disabled: this application is already installed.\n";
    echo "To re-install, remove config.php first, then delete the install/ directory when finished.";
    exit;
}
