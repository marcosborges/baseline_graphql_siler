<?php declare(strict_types=1);

namespace App;

use Siler\GraphQL\Annotation\{Field, ObjectType};

/** @ObjectType() */
class Query
{
    /** @Field() */
    static public function helloWorld(): string
    {
        return 'Hello, World!';
    }
}