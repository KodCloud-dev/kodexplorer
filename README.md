# kodexplorer
docker for kodexplorer
# 1.快速启动
```
docker run -d -p 80:80 kodcloud/kodexplorer
```
# 2.实现数据持久化——创建数据目录并在启动时挂载
```
mkdir /data
docker run -d -p 80:80 -v /data:/var/www/html kodcloud/kodexplorer
```

# 3. 环境变量

`uid/gid`:

- `PUID` 代表站点运行用户`nginx`的用户`uid`
- `PGID` 代表站点运行用户`nginx`的用户组`gid`

`php参数`:
- `FPM_MAX` php-fpm最大进程数, 默认50
- `FPM_START` php-fpm初始进程数, 默认10
- `FPM_MIN_SPARE` php-fpm最小空闲进程数, 默认10
- `FPM_MAX_SPARE` php-fpm最大空闲进程数, 默认30
