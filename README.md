# kodexplorer

docker for kodexplorer

镜像基于 `php:8.5.12-fpm-alpine3.24`，包含 CVE-2026-109618 和 CVE-2026-109619 的修复。修改 Dockerfile 后需要重新构建并使用新镜像重建容器；仅重启旧容器不会生效。

## 1. 快速启动

```bash
docker run -d -p 80:80 kodcloud/kodexplorer
```

## 2. 实现数据持久化——创建数据目录并在启动时挂载

```bash
mkdir /data
docker run -d -p 80:80 -v /data:/var/www/html kodcloud/kodexplorer
```

## 3. 以 https 方式启动

证书文件名必须是 `fullchain.pem` 和 `privkey.pem`。容器发现这两个文件后会启用 443，并把 80 端口重定向到 https。

```bash
docker run -d -p 80:80 -p 443:443 \
  -v "你的证书目录":/etc/nginx/ssl \
  -v /data:/var/www/html \
  kodcloud/kodexplorer
```

## 4. 环境变量

`uid/gid`:

- `PUID` 代表站点运行用户 `nginx` 的用户 `uid`
- `PGID` 代表站点运行用户 `nginx` 的用户组 `gid`

`站点自动更新`:

- `KODEXPLORER_AUTO_UPDATE` 默认 `1`。镜像内 kodexplorer 版本较新时，自动覆盖升级已有站点。
- 设置为 `0` 时，保留已有站点版本和文件，跳过镜像升级覆盖、升级赋权，以及 `pre-upgrade` / `post-upgrade` 钩子。`before-starting` 钩子仍会执行。
- 首次部署（`/var/www/html` 为空，忽略初始化锁文件）仍会正常初始化。已有子目录站点也会保留，不要求根目录存在 `config/version.php`。
- 此开关只控制容器启动时的镜像覆盖，不影响后台手动更新。PHP、Nginx 等运行环境仍随新镜像更新。
- `KODEXPLORER_UPDATE=1` 也遵守此开关，不会强制覆盖已有站点。

`php参数`:

- `FPM_MAX` php-fpm 最大进程数，默认 50
- `FPM_START` php-fpm 初始进程数，默认 10
- `FPM_MIN_SPARE` php-fpm 最小空闲进程数，默认 10
- `FPM_MAX_SPARE` php-fpm 最大空闲进程数，默认 30

四个 `FPM_*` 变量需要同时设置才会覆盖默认进程数。

## 5. 启动钩子

可执行的 `*.sh` 按文件名顺序运行，工作目录钩子如下：

- `/docker-entrypoint-hooks.d/pre-installation`
- `/docker-entrypoint-hooks.d/post-installation`
- `/docker-entrypoint-hooks.d/pre-upgrade`
- `/docker-entrypoint-hooks.d/post-upgrade`
- `/docker-entrypoint-hooks.d/before-starting`

钩子以站点用户执行。脚本返回非 0 时容器启动失败。

## 6. 站点权限

首次安装，或镜像内的新版本覆盖站点后，入口脚本会把 `/var/www/html` 的所有者修复为 `nginx:nginx`（兼容 `PUID` / `PGID`），并确保所有者可读写文件、可进入目录。不会沿符号链接修改站点外的目标。

以非 root 用户运行时不更改所有者，挂载目录需要预先授予该用户所有权。

## 7. 龙芯 LoongArch64 镜像

使用独立的 `Dockerfile.loong64`，基础镜像为 `lcr.loongnix.cn/library/php:8.4-alpine-fpm`。请在 LoongArch64 节点原生构建：

```bash
docker build -f Dockerfile.loong64 -t kodexplorer:loong64 .
docker run -d --name kodexplorer-loong64 -p 8080:80 \
  -v kodexplorer-loong64-data:/var/www/html kodexplorer:loong64
```

打开 `http://节点IP:8080` 完成安装。构建阶段的 Alpine 软件源默认使用阿里云镜像，最终镜像恢复基础镜像的软件源配置。可通过 `--build-arg ALPINE_MIRROR=https://dl-cdn.alpinelinux.org/alpine` 切换。默认使用 8 个编译任务，可通过 `--build-arg BUILD_JOBS=4` 降低构建资源占用。
