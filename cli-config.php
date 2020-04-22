<?php declare(strict_types=1);

use Doctrine\ORM\Tools\Console\ConsoleRunner;

require_once __DIR__ . '/bootstrap.php';
global $context;

return ConsoleRunner::createHelperSet($context->em);