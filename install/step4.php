<?php

/**
 *  PHP Mikrotik Billing (https://github.com/hotspotbilling/phpnuxbill/)
 *  by https://t.me/ibnux
 **/

require __DIR__ . '/_guard.php';

//error_reporting (0);
$appurl = $_POST['appurl'];
$db_host = $_POST['dbhost'];
$db_user = $_POST['dbuser'];
$db_pass = $_POST['dbpass'];
$db_name = $_POST['dbname'];
$cn = '0';
try {
    $dbh = new pdo(
        "mysql:host=$db_host;dbname=$db_name",
        "$db_user",
        "$db_pass",
        array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION)
    );
    $cn = '1';
} catch (PDOException $ex) {
    $cn = '0';
}

if ($cn == '1') {
    // Build config.php with var_export() so credentials containing quotes,
    // backslashes or "$"/"{" cannot break out of the string context and inject
    // PHP code into the generated config file.
    $useRadius = (isset($_POST['radius']) && $_POST['radius'] == 'yes');

    $input = '<?php
$protocol = (!empty($_SERVER["HTTPS"]) && $_SERVER["HTTPS"] !== "off" || $_SERVER["SERVER_PORT"] == 443) ? "https://" : "http://";
$host = $_SERVER["HTTP_HOST"];
$baseDir = rtrim(dirname($_SERVER["SCRIPT_NAME"]), "/\\\\");
define("APP_URL", $protocol . $host . $baseDir);

// Live, Dev, Demo
$_app_stage = "Live";

// Database PHPNuxBill
$db_host = ' . var_export($db_host, true) . ';
$db_user = ' . var_export($db_user, true) . ';
$db_pass = ' . var_export($db_pass, true) . ';
$db_name = ' . var_export($db_name, true) . ';
';

    if ($useRadius) {
        $input .= '
// Database Radius
$radius_host = ' . var_export($db_host, true) . ';
$radius_user = ' . var_export($db_user, true) . ';
$radius_pass = ' . var_export($db_pass, true) . ';
$radius_name = ' . var_export($db_name, true) . ';
';
    }

    $input .= '
if($_app_stage!="Live"){
    error_reporting(E_ERROR);
    ini_set("display_errors", 1);
    ini_set("display_startup_errors", 1);
}else{
    error_reporting(E_ERROR);
    ini_set("display_errors", 0);
    ini_set("display_startup_errors", 0);
}';

    $wConfig = "../config.php";
    $fh = fopen($wConfig, 'w') or die("Can't create config file, your server does not support the 'fopen' function. Please create config.php manually.");
    fwrite($fh, $input);
    fclose($fh);
    $sql = file_get_contents('phpnuxbill.sql');
    $qr = $dbh->exec($sql);
    if ($useRadius) {
        $sql = file_get_contents('radius.sql');
        $qrs = $dbh->exec($sql);
    }
} else {
    header("location: step3.php?_error=1");
    exit;
}

?>
<!DOCTYPE html>
<html lang="en">

<head>
    <title>PHPNuxBill Installer</title>
    <link rel="shortcut icon" type="image/x-icon" href="img/favicon.ico">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!--[if lt IE 9]>
    <script src="http://html5shim.googlecode.com/svn/trunk/html5.js"></script>
    <![endif]-->

    <link type='text/css' href='css/style.css' rel='stylesheet' />
    <link type='text/css' href="css/bootstrap.min.css" rel="stylesheet">
</head>

<body style='background-color: #FBFBFB;'>
    <div id='main-container'>
        <img src="img/logo.png" class="img-responsive" alt="Logo" />
        <hr>

        <div class="span12">
            <h4> PHPNuxBill Installer </h4>
            <?php
            if ($cn == '1') {
            ?>
                <p><strong>Config File Created and Database Imported.</strong><br></p>
                <form action="step5.php" method="post">
                    <fieldset>
                        <legend>Click Continue</legend>
                        <button type='submit' class='btn btn-primary'>Continue</button>
                    </fieldset>
                </form>
            <?php
            } elseif ($cn == '2') {
            ?>
                <p> MySQL Connection was successfull. An error occured while adding data on MySQL. Unsuccessfull
                    Installation. Please refer manual installation in the website github.com/ibnux/phpnuxbill/wiki or Contact Telegram @ibnux  for
                    helping on installation</p>
            <?php
            } else {
            ?>
                <p> MySQL Connection Failed.</p>
            <?php
            }
            ?>
        </div>
    </div>

    <div class="footer">Copyright &copy; 2021 PHPNuxBill. All Rights Reserved<br /><br /></div>
</body>

</html>
