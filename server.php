#!/usr/bin/env php
<?php declare(strict_types=1);

use Siler\Route;
use function Siler\Swoole\{graphql_handler, http, json, not_found};

require_once __DIR__ . '/bootstrap.php';

$health = fn() => json(['status' => 'ok']);
$graphql = graphql_handler($schema, $root_value, $context);

$handler = function () use ($health, $graphql): void {
    Route\get('/health', $health);
    Route\post('/graphql', $graphql);

    if (!Route\did_match()) {
        not_found();
    }
};

$server = http($handler, 9501);
$server->start();
