#!/usr/bin/env bash
# restore.sh — 从迁移包恢复：images、volumes、binds、compose、runs
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BUNDLE_DIR"

say()  { echo -e "\033[1;34m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[1;31m$*\033[0m"; }

# -------- 预检查 --------
if ! command -v jq >/dev/null 2>&1; then
  err "[ERR] 需要 jq，请先安装后再运行（apt/yum/dnf/zypper/apk 均可安装）"
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  err "[ERR] 需要 docker，请先安装并启动后再运行"
  exit 1
fi

# -------- A. 加载镜像 --------
say "[A] 加载镜像（如 images.tar 存在）"
if [[ -f images.tar ]]; then
  docker load -i images.tar
else
  warn "images.tar 不存在，将按需在线拉取镜像"
fi

# -------- B. 创建自定义网络 --------
say "[B] 创建自定义网络（如有）"
if jq -e '.networks|length>0' manifest.json >/dev/null; then
  while IFS= read -r n; do
    case "$n" in
      bridge|host|none) : ;;
      *)
        docker network create "$n" >/dev/null 2>&1 || true
        ;;
    esac
  done < <(jq -r '.networks[]' manifest.json)
fi

# -------- C. 回灌命名卷 --------
say "[C] 回灌命名卷"
if jq -e '.volumes|length>0' manifest.json >/dev/null; then
  mkdir -p volumes
  while IFS= read -r row; do
    vname=$(jq -r '.name' <<<"$row")
    file="vol_${vname}.tgz"
    if [[ ! -f "volumes/$file" ]]; then
      warn "  跳过 $vname（缺少 volumes/$file）"
      continue
    fi
    echo "  - ${vname}"
    docker volume create "$vname" >/dev/null 2>&1 || true
    docker run --rm -v "${vname}:/to" -v "$PWD/volumes:/from" alpine:3.20 \
      sh -c "cd /to && tar -xzf /from/${file}"
  done < <(jq -c '.volumes[]' manifest.json)
fi

# -------- D. 回灌绑定目录 --------
say "[D] 回灌绑定目录"
if jq -e '.binds|length>0' manifest.json >/dev/null; then
  mkdir -p binds
  while IFS= read -r row; do
    host=$(jq -r '.host' <<<"$row")
    file=$(jq -r '.file' <<<"$row")
    echo "  - ${host}"
    mkdir -p "$host"
    tar -C / -xzf "binds/${file}"
  done < <(jq -c '.binds[]' manifest.json)
fi

# -------- E. 恢复 Compose 项目（含：启动前清理同名 *_default 网络） --------
say "[E] 恢复 Compose 项目"
if jq -e '.projects|length>0' manifest.json >/dev/null; then
  mkdir -p compose_restore
  while IFS= read -r row; do
    name=$(jq -r '.name' <<<"$row")
    echo "  - project: $name"
    mkdir -p "compose_restore/${name}"

    # 解出可能的打包 compose 文件
    if compgen -G "compose/${name}/*.tgz" > /dev/null; then
      for t in compose/${name}/*.tgz; do
        tar -xzf "$t" -C "compose_restore/${name}" 2>/dev/null || true
      done
    fi
    # 复制可能存在的原始 compose 文件
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml .env docker-compose.override.yml compose.override.yaml; do
      [[ -f "compose/${name}/${f}" ]] && cp -a "compose/${name}/${f}" "compose_restore/${name}/${f}" || true
    done

    # 统一在 up -d 前：down + 清理同名默认网络，避免“标签不匹配/外部网络”报错
    NET="${name}_default"

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
      (
        cd "compose_restore/${name}"
        docker compose down || true
        docker network rm "$NET" >/dev/null 2>&1 || true
        docker compose up -d
      )
    elif command -v docker-compose >/dev/null 2>&1; then
      (
        cd "compose_restore/${name}"
        docker-compose down || true
        docker network rm "$NET" >/dev/null 2>&1 || true
        docker-compose up -d
      )
    else
      warn "  新机未安装 docker compose/docker-compose，跳过该项目"
    fi
  done < <(jq -c '.projects[]' manifest.json)
fi

# -------- F. 恢复单容器（非 Compose） --------
say "[F] 恢复单容器（非 Compose）"
if jq -e '.runs|length>0' manifest.json >/dev/null; then
  while IFS= read -r r; do
    echo "  - $r"
    bash "$r" || true
  done < <(jq -r '.runs[]' manifest.json)
fi

# -------- G. 完成 --------
say "[G] 完成，当前容器："
docker ps --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo "提示：若端口被占用，请编辑 compose 或 runs 脚本后再次执行。"
