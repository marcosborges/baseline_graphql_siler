RUN docker-php-ext-install mbstring
#RUN docker-php-ext-install radius
#RUN apt-get find php*
RUN pecl install radius-1.4.0b1
RUN pear install Auth_RADIUS
#RUN pecl install memcached 
RUN apt-get install iputils-ping -y
RUN apt-get install mariadb-client-10.3 -y