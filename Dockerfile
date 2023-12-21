FROM php:8.2-fpm-alpine3.18

ENV KODEXPLORER_VERSION 4.52

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

# entrypoint.sh and dependencies
RUN set -ex; \
    \
    apk update && apk upgrade &&\
    apk add --no-cache \
        bash \
        rsync \
	    supervisor \
        imagemagick \
        ffmpeg \
        tzdata \
        unzip \
	    nginx \
	    # forward request and error logs to docker log collector
        && ln -sf /dev/stdout /var/log/nginx/access.log \
        && ln -sf /dev/stderr /var/log/nginx/error.log \
        && mkdir -p /run/nginx \
        && mkdir -p /var/log/supervisor && \
	cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
	echo "Asia/Shanghai" > /etc/timezone

ADD conf/supervisord.conf /etc/supervisord.conf

# Copy our nginx config
RUN rm -Rf /etc/nginx/nginx.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf

# nginx site conf
RUN mkdir -p /etc/nginx/sites-available/; \
    mkdir -p /etc/nginx/sites-enabled/; \
    mkdir -p /etc/nginx/ssl/; \
    rm -Rf /var/www/*; \
    mkdir /var/www/html/; \
    chown -R nginx:root /var/www; \
    chmod -R g=u /var/www

ADD conf/private-ssl.conf /etc/nginx/sites-available/private-ssl.conf

# install the PHP extensions we need
RUN set -ex; \
    \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        autoconf \
        freetype-dev \
        icu-dev \
        libevent-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libmemcached-dev \
        libxml2-dev \
        libzip-dev \
        pcre-dev \
        libwebp-dev \
    ; \
    \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure intl; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        opcache \
        pcntl \
        zip \
    ; \
    \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-network --virtual .kodexplorer-phpext-rundeps $runDeps; \
    apk del .build-deps

# tweak php-fpm config
ENV fpm_conf /usr/local/etc/php-fpm.d/www.conf
ENV php_vars /usr/local/etc/php/conf.d/docker-vars.ini
RUN { \
        echo 'opcache.enable=1'; \
        echo 'opcache.interned_strings_buffer=32'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.revalidate_freq=60'; \
        echo 'opcache.jit=1255'; \
        echo 'opcache.jit_buffer_size=128M'; \
    } > "${PHP_INI_DIR}/conf.d/opcache-recommended.ini"; \
    \
    echo "cgi.fix_pathinfo=1" > ${php_vars} &&\
    echo "upload_max_filesize = 512M"  >> ${php_vars} &&\
    echo "post_max_size = 512M"  >> ${php_vars} &&\
    echo "memory_limit = 512M"  >> ${php_vars} && \
    echo "max_execution_time = 3600"  >> ${php_vars} && \
    echo "max_input_time = 3600"  >> ${php_vars} && \
    sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 50/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 10/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 10/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 30/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 500/g" \
        -e "s/user = www-data/user = nginx/g" \
        -e "s/group = www-data/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = www-data/listen.owner = nginx/g" \
        -e "s/;listen.group = www-data/listen.group = nginx/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf}

VOLUME /var/www/html

RUN set -ex; \
    curl -fsSL -o kodexplorer.zip \
		"https://static.kodcloud.com/update/download/kodexplorer${KODEXPLORER_VERSION}.zip"; \ 
    unzip kodexplorer.zip -d /usr/src/kodexplorer/; \
    curl -fsSL -o update.zip \
        "http://static.kodcloud.com/update/update/2.0-${KODEXPLORER_VERSION}.zip"; \
    mv update.zip /usr/src/kodexplorer/; \
    rm kodexplorer.zip

COPY entrypoint.sh /

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord","-n","-c","/etc/supervisord.conf"]
