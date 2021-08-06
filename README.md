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