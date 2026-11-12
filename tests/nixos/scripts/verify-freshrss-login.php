<?php

$arguments = $argv ?? [];
if (count($arguments) !== 3) {
    throw new InvalidArgumentException('Supply the system and user configuration paths.');
}
$system = require $arguments[1];
$user = require $arguments[2];
exit($system['default_user'] === 'runtime-reader' && password_verify('vm-fixture-password', $user['passwordHash']) ? 0 : 1);
