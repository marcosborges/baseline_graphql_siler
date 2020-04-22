<?php declare(strict_types=1);

use App\Context;
use App\Query;
use Doctrine\ORM\EntityManager;
use Doctrine\ORM\Tools\Setup;
//use Dotenv\Dotenv;
use Monolog\Handler\ErrorLogHandler;
use Siler\Monolog as Log;
use function Siler\Env\env_var;
use function Siler\GraphQL\annotated;

require_once __DIR__ . '/vendor/autoload.php';

//Dotenv::createImmutable(__DIR__)->load();
Log\handler(new ErrorLogHandler());

$schema = annotated([Query::class]);
$root_value = null;
$context = new Context();

$dev_mode = env_var('APP_ENV') === 'development';
$config = Setup::createAnnotationMetadataConfiguration([__DIR__ . '/src'], $dev_mode, null, null, false);

$conn = [
    'driver' => 'pdo_sqlite',
    'path' => __DIR__ . '/db.sqlite',
];

$context->em = EntityManager::create($conn, $config);