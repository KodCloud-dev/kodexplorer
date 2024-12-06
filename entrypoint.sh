#!/bin/sh
set -eu

# version_greater A B returns whether A > B
version_greater() {
    [ "$(printf '%s\n' "$@" | sort -t '.' -n -k1,1 -k2,2 -k3,3 -k4,4 | head -n 1)" != "$1" ]
}

# return true if specified directory is empty
directory_empty() {
    [ -z "$(ls -A "$1/")" ]
}

if [ -n "${PUID+x}" ]; then
    if [ ! -n "${PGID+x}" ]; then
        PGID=${PUID}
    fi
    deluser nginx
    addgroup -g ${PGID} nginx
    adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
    chown -R nginx:nginx /var/lib/nginx/
fi

if [ -n "${FPM_MAX+x}" ] && [ -n "${FPM_START+x}" ] && [ -n "${FPM_MIN_SPARE+x}" ] && [ -n "${FPM_MAX_SPARE+x}" ]; then
    sed -i "s/pm.max_children = .*/pm.max_children = ${FPM_MAX}/g" /usr/local/etc/php-fpm.d/www.conf
    sed -i "s/pm.start_servers = .*/pm.start_servers = ${FPM_START}/g" /usr/local/etc/php-fpm.d/www.conf
    sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = ${FPM_MIN_SPARE}/g" /usr/local/etc/php-fpm.d/www.conf
    sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = ${FPM_MAX_SPARE}/g" /usr/local/etc/php-fpm.d/www.conf
fi

if expr "$1" : "supervisord" 1>/dev/null || [ "${KODEXPLORER_UPDATE:-0}" -eq 1 ]; then
    uid="$(id -u)"
    gid="$(id -g)"
    if [ "$uid" = '0' ]; then
        user='nginx'
        group='nginx'
    else
        user="$uid"
        group="$gid"
    fi

    # If another process is syncing the html folder, wait for
    # it to be done, then escape initalization.
    (
        if ! flock -n 9; then
            # If we couldn't get it immediately, show a message, then wait for real
            echo "Another process is initializing kodexplorer. Waiting..."
            flock 9
        fi

        installed_version="0.0.0"
        if [ -f /var/www/html/config/version.php ]; then
            # shellcheck disable=SC2016
            installed_version="$(php -r 'require "/var/www/html/config/version.php"; echo KOD_VERSION . "." . KOD_VERSION_BUILD;')"
        fi
        # shellcheck disable=SC2016
        image_version="$(php -r 'require "/usr/src/kodexplorer/config/version.php"; echo KOD_VERSION . "." . KOD_VERSION_BUILD;')"

        if version_greater "$image_version" "$installed_version"; then
            echo "Initializing kodexplorer $image_version ..."
            if [ "$installed_version" != "0.0.0" ]; then
                echo "Upgrading kodexplorer from $installed_version ..."
            fi
            if [ "$(id -u)" = 0 ]; then
                rsync_options="-rlDog --chown $user:$group"
            else
                rsync_options="-rlD"
            fi

            # Install
            if [ "$installed_version" = "0.0.0" ]; then
                echo "New kodexplorer instance"
                rsync $rsync_options --exclude '/*.zip' /usr/src/kodexplorer/ /var/www/html/
                
            # Upgrade
            else
                if [ -f "/usr/src/kodexplorer/update.zip" ]; then
                    unzip -o /usr/src/kodexplorer/update.zip -d /usr/src/update
                    rsync $rsync_options /usr/src/update/ /var/www/html/
                fi
            fi
            echo "Initializing finished"
        fi

    ) 9> /var/www/html/kodexplorer-init-sync.lock

fi

if [ -f /etc/nginx/ssl/fullchain.pem ] && [ -f /etc/nginx/ssl/privkey.pem ] && [ ! -f /etc/nginx/sites-enabled/*-ssl.conf ] ; then
        ln -s /etc/nginx/sites-available/private-ssl.conf /etc/nginx/sites-enabled/
        sed -i "s/#return 301/return 301/g" /etc/nginx/sites-available/default.conf
fi

exec "$@"

