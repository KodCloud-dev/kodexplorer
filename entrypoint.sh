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

run_as() {
    if [ "$(id -u)" = 0 ]; then
        su -p "$user" -s /bin/sh -c "$1"
    else
        sh -c "$1"
    fi
}

# Repair existing files as well as files copied from the image/update archive.
# Do not follow symlinks into storage mounted outside the site directory.
fix_site_permissions() {
    echo "Setting kodexplorer site permissions for $user:$group ..."
    if [ "$(id -u)" = 0 ]; then
        chown -hR "$user:$group" /var/www/html
    fi
    find /var/www/html -type d -exec chmod u+rwx {} +
    find /var/www/html -type f -exec chmod u+rw {} +
}

# Execute all executable files in a given directory in alphanumeric order
run_path() {
    local hook_folder_path="/docker-entrypoint-hooks.d/$1"

    if ! [ -d "${hook_folder_path}" ]; then
        echo "=> Skipping the folder \"${hook_folder_path}\", because it doesn't exist"
        return 0
    fi

    echo "=> Searching for scripts (*.sh) to run, located in the folder: ${hook_folder_path}"

    find "${hook_folder_path}" -type f -maxdepth 1 -iname '*.sh' -print | sort | while read -r script_file_path; do
        if ! [ -x "${script_file_path}" ]; then
            echo "==> The script \"${script_file_path}\" was skipped, because it didn't have the executable flag"
            continue
        fi

        echo "==> Running the script (cwd: $(pwd)): \"${script_file_path}\""

        if run_as "${script_file_path}"; then
            echo "==> Finished the script: \"${script_file_path}\""
        else
            echo "==> Failed at executing \"${script_file_path}\". Exit code: $?"
            exit 1
        fi
    done
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

        # A mounted subdirectory site has no config/version.php at the html root.
        # Ignore our lock file when deciding whether this is an empty first install.
        if [ "${KODEXPLORER_AUTO_UPDATE:-1}" = "0" ] && \
            [ -n "$(find /var/www/html -mindepth 1 -maxdepth 1 ! -name kodexplorer-init-sync.lock -print -quit)" ]; then
            echo "Keeping existing site (KODEXPLORER_AUTO_UPDATE=0); skipping image initialization and upgrade."
        elif version_greater "$image_version" "$installed_version"; then
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
                run_path pre-installation
                rsync $rsync_options --exclude '/*.zip' /usr/src/kodexplorer/ /var/www/html/
                fix_site_permissions
                run_path post-installation
            # Upgrade
            else
                run_path pre-upgrade

                if [ -f "/usr/src/kodexplorer/update.zip" ]; then
                    unzip -o /usr/src/kodexplorer/update.zip -d /usr/src/update
                    rsync $rsync_options /usr/src/update/ /var/www/html/
                fi

                fix_site_permissions
                run_path post-upgrade
            fi
            echo "Initializing finished"
        fi

    ) 9> /var/www/html/kodexplorer-init-sync.lock

    run_path before-starting
fi

if [ -f /etc/nginx/ssl/fullchain.pem ] && [ -f /etc/nginx/ssl/privkey.pem ] && [ ! -f /etc/nginx/sites-enabled/*-ssl.conf ] ; then
    ln -s /etc/nginx/sites-available/private-ssl.conf /etc/nginx/sites-enabled/
    sed -i "s/#return 301/return 301/g" /etc/nginx/nginx.conf
fi

exec "$@"
