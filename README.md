# **🐳 Docker Migrate — 好用的Docker一键迁移脚本**

> 🚀 全自动迁移 Docker：镜像、网络、数据卷、绑定目录、Compose 配置、1Panel 应用——统统一键打包恢复！

------

## **✨ 功能亮点**

- 🔍 **自动识别独立容器与 Compose 组**

  自动分组显示独立容器与 Compose 组，一次选中整组（支持 1Panel / Portainer / 自建 compose）。

- 📦 **完整迁移你的 Docker 环境**

  - Docker 镜像（含 images.tar）
  - 命名卷（volume）
  - 绑定目录（bind mount）
  - Docker网络
  - Compose 配置文件（含 1Panel 的绝对路径 yaml）
  - 自动生成恢复脚本 restore.sh

- 🔁 **新服务器一键恢复**

  自动解压、重建卷、恢复绑定目录、恢复 compose、自动拉起容器。

- 🔐 **安全的迁移包传输方式**

  使用随机 Token 的安全路径：

  http://IP:PORT/<RANDOM>/<BUNDLE>.tar.gz

  非目标路径全部返回 404，避免端口被扫，导致文件泄露。

- ⚙️ **自动检测端口占用、本机 IP、缺失依赖等**

  开箱即用，小白也能轻松迁移服务器。

## **🧭 使用方法**

------

## **🖥️ ① 在旧服务器执行（生成迁移包）**

> **推荐直接使用 curl 版本（始终拉最新脚本）**

```shell
bash <(curl -fsSL https://raw.githubusercontent.com/lx969788249/docker_migrate/master/docker_migrate_perfect.sh)
```

脚本会：

1. 自动检测并安装缺失依赖（docker、jq、python3…）
2. 自动检测所有容器 → 自动分组显示
3. 选择你想迁移的容器（支持“整组 compose”）
4. 是否停机备份（推荐数据库勾选停机）
5. 打包所有数据（镜像 / 卷 / 绑定目录 / compose 配置）
6. 启动带随机 URL 的临时 HTTP 服务，输出下载链接，例如：

```shell
http://192.168.1.1:8080/XyZ83mqP10/Mlq1n3069T.tar.gz
```

> ⚠️ **请务必复制此链接到新服务器执行恢复操作。**

退出脚本时，会自动：

- ❎ 关闭 HTTP 服务
- 🔄 若之前停机，会自动重启所有容器
- 🧹 删除临时打包目录与 tar.gz 文件

------

## **💻 ② 在新服务器执行（自动恢复）**

运行恢复脚本：

```shell
bash <(curl -fsSL https://raw.githubusercontent.com/lx969788249/docker_migrate/master/auto_restore.sh)
```

脚本会要求粘贴旧服务器输出的链接，例如：

```shell
http://198.51.100.25:8080/XyZ83mqP10/Mlq1n3069T.tar.gz
```

恢复过程包括：

- 🎯 下载迁移包
- 📦 解压 bundle
- 🐳 导入镜像 (docker load)
- 📁 回灌所有 volume / bind mount
- 🧩 恢复 compose 项目（含 1Panel 的绝对路径 YAML）
- 🚀 自动拉起所有容器

恢复结束后，会输出当前的容器列表。

## **📌 支持场景示例**

- 从一台 VPS 迁移到另一台 VPS
- 从物理机迁移到云服务器
- 迁移 1Panel / Portainer / 自建 Docker Compose 项目
- 更换服务器系统或 SSD
- 解决“镜像无法下载、国内拉取太慢”等情况

------

## **⚠️ 注意事项**

- HTTP 传输为明文，仅建议在可信网络使用。
- 移动数据库类服务建议选择停机备份以确保一致性。
- 若你的容器路径非常特殊（比如挂载到无权限路径），需确保 root 用户有访问权。

------

## **⭐️ 支持一下**

如果这个项目帮到了你，欢迎来个 Star！

也欢迎提交 Issue / PR 来一起优化功能。

------

## **🧑‍💻 作者**

MIT License © lx969788249

------

