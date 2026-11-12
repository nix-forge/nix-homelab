<?php

declare(strict_types=1);

// Provision through the upstream PHP APIs; native getopt() cannot accept
// credentials injected into PHP's argv after process startup.
require getenv('FRESHRSS_PACKAGE') . '/cli/_cli.php';
$credentials = getenv('CREDENTIALS_DIRECTORY');
if ($credentials === false || $credentials === '') {
    throw new RuntimeException('Missing FreshRSS credential directory');
}
$usernameContents = file_get_contents($credentials . '/news-username');
if ($usernameContents === false) {
    throw new RuntimeException('Could not read the FreshRSS runtime username');
}
$passwordContents = file_get_contents($credentials . '/news-password');
if ($passwordContents === false) {
    throw new RuntimeException('Could not read the FreshRSS runtime password');
}
$username = rtrim($usernameContents, "\n");
$password = rtrim($passwordContents, "\n");
if (!preg_match('/^[A-Za-z0-9_][A-Za-z0-9_.@-]{1,38}$/D', $username) ||
    !FreshRSS_user_Controller::checkUsername($username) || $password === '' ||
    strpbrk($password, "\r\n\0") !== false) {
    fail('Invalid FreshRSS runtime credential');
}
$settings = FreshRSS_Context::systemConf();
if (FreshRSS_user_Controller::userExists($username)) {
    cliInitUser($username);
    if (!FreshRSS_user_Controller::updateUser($username, null, $password)) {
        fail('FreshRSS runtime user update failed');
    }
} else {
    if ($settings->default_user !== 'provision_pending' || FreshRSS_user_Controller::listUsers() !== []) {
        fail('FreshRSS account migration is required before activation');
    }
    if (!FreshRSS_user_Controller::createUser($username, null, $password, [], false)) {
        fail('FreshRSS runtime user creation failed');
    }
}
$settings->default_user = $username;
if (!$settings->save()) {
    fail('FreshRSS administrator configuration could not be saved');
}
invalidateHttpCache($username);
accessRights();
