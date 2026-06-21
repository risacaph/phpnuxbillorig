<?php

/**
 *  PHP Mikrotik Billing (https://github.com/hotspotbilling/phpnuxbill/)
 *  by https://t.me/ibnux
 **/


class Csrf
{
    private static $tokenExpiration = 7200; // 2 hours, refreshed on every page render (sliding)

    public static function generateToken($length = 16)
    {
        return bin2hex(random_bytes($length));
    }

    /**
     * Return the stable per-session CSRF token, creating it once if needed.
     * The expiry is refreshed on each call so active users keep a valid token.
     */
    public static function getToken()
    {
        if (empty($_SESSION['csrf_token'])) {
            $_SESSION['csrf_token'] = self::generateToken();
        }
        $_SESSION['csrf_token_time'] = time();
        return $_SESSION['csrf_token'];
    }

    public static function validateToken($token, $storedToken)
    {
        return hash_equals((string) $storedToken, (string) $token);
    }

    /**
     * Validate a supplied token against the stored session token (with expiry).
     */
    public static function verify($token)
    {
        if (empty($_SESSION['csrf_token']) || empty($token)) {
            return false;
        }
        if (isset($_SESSION['csrf_token_time']) && (time() - $_SESSION['csrf_token_time'] > self::$tokenExpiration)) {
            self::clearToken();
            return false;
        }
        return self::validateToken($token, $_SESSION['csrf_token']);
    }

    public static function check($token)
    {
        global $config, $isApi;
        if (($config['csrf_enabled'] ?? '') == 'yes' && !$isApi) {
            return self::verify($token);
        }
        return true;
    }

    /**
     * Central CSRF enforcement for state-changing web requests. Call early in
     * the request lifecycle (the router). API requests, the kill-switch
     * (csrf_enabled = 'no'), and the listed exempt handlers (external webhooks
     * and captive-portal posts that cannot carry our token) are skipped.
     */
    public static function enforce($handler = '', $exempt = [])
    {
        global $config, $isApi;
        if ($isApi) {
            return;
        }
        if (($config['csrf_enabled'] ?? '') === 'no') {
            return; // explicit kill-switch
        }
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        if (!in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'], true)) {
            return;
        }
        if (in_array($handler, $exempt, true)) {
            return;
        }
        $token = $_POST['csrf_token'] ?? ($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
        if (!self::verify($token)) {
            http_response_code(419);
            header('Content-Type: text/plain; charset=utf-8');
            die('Invalid or expired security token (CSRF). Please reload the page and try again.');
        }
    }

    public static function generateAndStoreToken()
    {
        // Backward-compatible: now returns the stable per-session token instead
        // of rotating it, so every form on the page shares one valid token.
        return self::getToken();
    }

    public static function clearToken()
    {
        unset($_SESSION['csrf_token'], $_SESSION['csrf_token_time']);
    }
}
