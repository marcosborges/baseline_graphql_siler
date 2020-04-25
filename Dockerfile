FROM phpswoole/swoole
RUN pecl install xdebug && pecl install pcov && docker-php-ext-enable pcov
RUN composer require pcov/clobber --dev

COPY . /var/www



