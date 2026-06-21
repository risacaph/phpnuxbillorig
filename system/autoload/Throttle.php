<?php

/**
 *  PHP Mikrotik Billing (https://github.com/hotspotbilling/phpnuxbill/)
 *  by https://t.me/ibnux
 *
 *  Lightweight, schema-free brute-force throttle for login/OTP endpoints.
 *  Failed attempts are recorded per key (typically per client IP) as
 *  timestamps in a JSON file under system/cache/throttle/. It deliberately
 *  fails OPEN: if the cache directory is unwritable it never blocks a
 *  legitimate user, it just stops providing protection.
 **/

class Throttle
{
    private static function dir()
    {
        global $CACHE_PATH;
        $base = (!empty($CACHE_PATH) ? $CACHE_PATH : (__DIR__ . DIRECTORY_SEPARATOR . '..' . DIRECTORY_SEPARATOR . 'cache'))
            . DIRECTORY_SEPARATOR . 'throttle';
        if (!is_dir($base)) {
            @mkdir($base, 0750, true);
        }
        return $base;
    }

    private static function file($key)
    {
        return self::dir() . DIRECTORY_SEPARATOR . sha1($key) . '.json';
    }

    private static function recent($file, $window)
    {
        if (!is_file($file)) {
            return [];
        }
        $times = json_decode(@file_get_contents($file), true);
        if (!is_array($times)) {
            return [];
        }
        $now = time();
        return array_values(array_filter($times, function ($t) use ($now, $window) {
            return is_numeric($t) && ($now - $t) < $window;
        }));
    }

    /**
     * @return bool true if there have been >= $maxAttempts failures within $window seconds
     */
    public static function tooManyAttempts($key, $maxAttempts = 10, $window = 300)
    {
        return count(self::recent(self::file($key), $window)) >= $maxAttempts;
    }

    public static function registerFailure($key, $window = 300)
    {
        $file = self::file($key);
        $times = self::recent($file, $window);
        $times[] = time();
        @file_put_contents($file, json_encode($times), LOCK_EX);
    }

    public static function clear($key)
    {
        $file = self::file($key);
        if (is_file($file)) {
            @unlink($file);
        }
    }

    public static function clientIp()
    {
        foreach (['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR', 'HTTP_CLIENT_IP', 'REMOTE_ADDR'] as $h) {
            if (!empty($_SERVER[$h])) {
                $ip = $_SERVER[$h];
                if (strpos($ip, ',') !== false) {
                    $ip = trim(explode(',', $ip)[0]);
                }
                return $ip;
            }
        }
        return 'unknown';
    }
}
