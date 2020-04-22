<?php declare(strict_types=1);

namespace App;

use Doctrine\ORM\EntityManager;

class Context
{
    public EntityManager $em;
}