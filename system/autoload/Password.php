<?php

/**
 *  PHP Mikrotik Billing (https://github.com/hotspotbilling/phpnuxbill/)
 *  by https://t.me/ibnux
 **/

class Password
{

    public static function _crypt($password)
    {
        // Admin passwords: modern, salted hashing (bcrypt by default).
        return password_hash($password, PASSWORD_DEFAULT);
    }

    public static function _verify($user_input, $hashed_password)
    {
        if (empty($hashed_password)) {
            return false;
        }
        // Modern password_hash() values (bcrypt/argon2).
        $info = password_get_info($hashed_password);
        if (!empty($info['algo'])) {
            return password_verify($user_input, $hashed_password);
        }
        // Legacy unsalted SHA-1 hashes (40 hex chars). Constant-time compare;
        // these are transparently upgraded to bcrypt on next successful login.
        if (strlen($hashed_password) === 40 && ctype_xdigit($hashed_password)) {
            return hash_equals(strtolower($hashed_password), sha1($user_input));
        }
        return false;
    }

    /**
     * True when an admin password hash should be re-hashed with the current
     * algorithm (legacy SHA-1, or an outdated bcrypt cost/algorithm).
     */
    public static function _needsRehash($hashed_password)
    {
        $info = password_get_info($hashed_password);
        if (empty($info['algo'])) {
            return true;
        }
        return password_needs_rehash($hashed_password, PASSWORD_DEFAULT);
    }

    public static function _uverify($user_input, $hashed_password)
    {
        // Customer passwords are stored verbatim (they double as the Mikrotik /
        // RADIUS Cleartext-Password). Use a constant-time, non-type-juggling
        // compare so values like "0e123" cannot be matched against "0e456".
        return hash_equals((string) $hashed_password, (string) $user_input);
    }
    public static function _gen()
    {
        $pass = substr(str_shuffle(str_repeat('ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz@#!123456789', 8)), 0, 8);
        return $pass;
    }

    /**
     * verify CHAP password
     * @param string $realPassword
     * @param string $CHAPassword
     * @param string $CHAPChallenge
     * @return bool
     */
    public static function chap_verify($realPassword, $CHAPassword, $CHAPChallenge){
        $CHAPassword = substr($CHAPassword, 2);
        $chapid = substr($CHAPassword, 0, 2);
        $result = hex2bin($chapid) . $realPassword . hex2bin(substr($CHAPChallenge, 2));
        $response = $chapid . md5($result);
        return ($response != $CHAPassword);
    }
}
