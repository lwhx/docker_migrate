#!/usr/bin/env bash
set -euo pipefail

# 环境变量：
# RESTORE_KEEP=1         # 恢复成功后也不删除文件
# RESTORE_CLEAN_ALL=1    # 无论成功失败都删除文件（危险）

BLUE(){ echo -e "\033[1;34m$*\033[0m"; }
YEL(){  echo -e "\033[1;33m$*\033[0m"; }
RED(){  echo -e "\033[1;31m$*\033[0m"; }
OK(){   echo -e "\033[1;32m$*\033[0m"; }

asudo(){ if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi; }
pm_detect(){ if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
             if command -v dnf     >/dev/null 2>&1; then echo dnf; return; fi
             if command -v yum     >/dev/null 2>&1; then echo yum; return; fi
             if command -v zypper  >/dev/null 2>&1; then echo zypper; return; fi
             if command -v apk     >/dev/null 2>&1; then echo apk; return; fi
             echo none; }
pm_install(){
  local pm="$1"; shift
  case "$pm" in
    apt)
      asudo apt-get update -y
      asudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
      ;;
    dnf)    asudo dnf install -y "$@" ;;
    yum)    asudo yum install -y "$@" ;;
    zypper) asudo zypper --non-interactive install -y "$@" ;;
    apk)    asudo apk add --no-cache "$@" ;;
    *)
      RED "[ERR] 不支持的包管理器：$pm，请手动安装：$*"
      return 1
      ;;
  esac
}

ensure_deps(){
  local PM; PM="$(pm_detect)"

  # 1) 基础依赖：curl / tar / jq / docker
  for bin in curl tar jq docker; do
    # 已安装则跳过
    if command -v "$bin" >/dev/null 2>&1; then
      continue
    fi

    if [[ "$PM" == "none" ]]; then
      RED "[ERR] 缺少依赖：$bin，请手动安装后再运行本脚本。"
      exit 1
    fi

    if [[ "$bin" == "docker" ]]; then
      YEL "[INFO] 未检测到 docker，尝试自动安装 ..."

      case "$PM" in
        apt)
          # Debian / Ubuntu：官方源一般提供 docker.io
          if ! pm_install "$PM" docker.io; then
            RED "[ERR] 通过 apt 安装 docker.io 失败，请手动安装 Docker 后重试。"
            exit 1
          fi
          ;;
        yum|dnf)
          # RHEL / CentOS / AlmaLinux 等：可能叫 docker 或 docker-ce
          if ! pm_install "$PM" docker; then
            pm_install "$PM" docker-ce || {
              RED "[ERR] 通过 $PM 安装 docker/docker-ce 失败，请手动安装 Docker 后重试。"
              exit 1
            }
          fi
          ;;
        zypper)
          if ! pm_install "$PM" docker; then
            RED "[ERR] 通过 zypper 安装 docker 失败，请手动安装 Docker 后重试。"
            exit 1
          fi
          ;;
        apk)
          if ! pm_install "$PM" docker; then
            RED "[ERR] 通过 apk 安装 docker 失败，请手动安装 Docker 后重试。"
            exit 1
          fi
          ;;
        *)
          RED "[ERR] 当前包管理器不支持自动安装 Docker，请手动安装。"
          exit 1
          ;;
      esac
    else
      # 普通依赖：包名 = 命令名
      YEL "[INFO] 安装依赖：$bin"
      pm_install "$PM" "$bin"
    fi
  done

  # 2) 尝试启动 docker
  if ! docker info >/dev/null 2>&1; then
    YEL "[INFO] 尝试启动 Docker 服务..."

    # systemd 场景
    if command -v systemctl >/dev/null 2>&1; then
      asudo systemctl enable --now docker >/dev/null 2>&1 || true
    fi

    # SysV/service 场景
    if ! docker info >/dev/null 2>&1 && command -v service >/dev/null 2>&1; then
      asudo service docker start >/dev/null 2>&1 || true
    fi

    # 兜底：没有 service 单元，就直接后台起 dockerd
    if ! docker info >/dev/null 2>&1 && command -v dockerd >/dev/null 2>&1; then
      YEL "[INFO] 直接后台启动 dockerd（日志：/var/log/dockerd.restore.log）..."
      asudo nohup dockerd >/var/log/dockerd.restore.log 2>&1 &
      sleep 3
    fi

    # 最终检查
    if ! docker info >/dev/null 2>&1; then
      RED "[ERR] Docker 未能启动，请确认在新服务器上正确安装并配置 Docker。"
      exit 1
    fi
  fi

  # 3) 尝试确保 docker compose / docker-compose 可用（最佳努力，不强制失败）
  if docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1; then
    OK "[OK] 已检测到 Docker Compose：$(docker compose version 2>/dev/null || docker-compose version 2>/dev/null)"
  else
    YEL "[INFO] 未检测到 docker compose / docker-compose，尝试自动安装 ..."
    local PM2; PM2="$PM"
    case "$PM2" in
      apt)
        pm_install "$PM2" docker-compose || YEL "[WARN] apt 安装 docker-compose 失败，请考虑手动安装。"
        ;;
      yum|dnf)
        pm_install "$PM2" docker-compose || YEL "[WARN] $PM2 安装 docker-compose 失败，请考虑手动安装。"
        ;;
      zypper)
        pm_install "$PM2" docker-compose || YEL "[WARN] zypper 安装 docker-compose 失败，请考虑手动安装。"
        ;;
      apk)
        pm_install "$PM2" docker-compose || YEL "[WARN] apk 安装 docker-compose 失败，请考虑手动安装。"
        ;;
      *)
        YEL "[WARN] 当前环境无法自动安装 Docker Compose，请手动安装 docker compose / docker-compose。"
        ;;
    esac

    if docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1; then
      OK "[OK] Docker Compose 安装完成：$(docker compose version 2>/dev/null || docker-compose version 2>/dev/null)"
    else
      YEL "[WARN] 仍未检测到 docker compose / docker-compose，恢复时将跳过 Compose 项目（但不会影响其他容器恢复）。"
    fi
  fi
}

prompt_url(){
  local u="${1:-}"
  if [[ -z "$u" ]]; then
    read -rp "请输入旧服务器的“一键包下载”链接（以 .tar.gz 结尾）： " u
  fi
  [[ "$u" =~ \.tar\.gz($|\?) ]] || { RED "[ERR] 链接必须以 .tar.gz 结尾"; exit 1; }
  echo "$u"
}

main(){
  ensure_deps

  local URL; URL="$(prompt_url "${1:-}")"
  local BASE="/root/docker_migrate_restore"
  mkdir -p "$BASE"

  # 生成临时ID目录
  local RID="$(basename "$URL" | sed 's/\.tar\.gz.*$//' | tr -dc 'A-Za-z0-9_-')"
  [[ -n "$RID" ]] || RID="$(date +%s)"
  local WORK="$BASE/$RID"
  mkdir -p "$WORK"

  BLUE "[INFO] 下载迁移包到 $WORK ..."
  local TARBALL="$WORK/bundle.tar.gz"
  if command -v curl >/dev/null 2>&1; then
    curl -fSL "$URL" -o "$TARBALL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$TARBALL" "$URL"
  else
    RED "[ERR] 需要 curl 或 wget 以下载迁移包。"
    exit 1
  fi
  OK "[OK] 下载完成：$TARBALL"

  BLUE "[INFO] 解压迁移包 ..."
  tar -C "$WORK" -xzf "$TARBALL"
  OK "[OK] 解压完成"

  # 自动寻找 manifest.json 和 restore.sh 所在目录（兼容多层目录）
  local BDIR="$WORK"
  if [[ ! -f "$BDIR/manifest.json" || ! -f "$BDIR/restore.sh" ]]; then
    local cand
    cand="$(find "$WORK" -maxdepth 3 -type f -name 'manifest.json' | head -n 1 || true)"
    if [[ -n "$cand" ]]; then
      BDIR="$(dirname "$cand")"
    fi
  fi

  if [[ ! -f "$BDIR/manifest.json" || ! -f "$BDIR/restore.sh" ]]; then
    RED "[ERR] 在解压目录中未找到 manifest.json 或 restore.sh，请检查迁移包是否完整。"
    exit 1
  fi

  BLUE "[INFO] 切换到恢复目录：$BDIR ..."
  cd "$BDIR"
  chmod +x restore.sh

  BLUE "[INFO] 开始执行恢复脚本 restore.sh ..."
  if ./restore.sh; then
    OK "[OK] 恢复脚本执行成功！"
    echo
    OK "[OK] 当前 Docker 容器："
    docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}"
    # 自动清理策略
    if [[ "${RESTORE_KEEP:-0}" == "1" ]]; then
      YEL "[INFO] 已按 RESTORE_KEEP=1 保留恢复目录：$BASE"
    else
      YEL "[INFO] 清理临时恢复目录（可通过 RESTORE_KEEP=1 禁用）..."
      rm -rf "$BASE"
      OK "[OK] 已清理：$BASE"
    fi
    exit 0
  else
    RED "[ERR] 恢复脚本运行失败，请检查上方日志。"
    YEL "[INFO] 为便于排查，保留恢复目录：$BASE"
    if [[ "${RESTORE_CLEAN_ALL:-0}" == "1" ]]; then
      YEL "[WARN] RESTORE_CLEAN_ALL=1：仍将强制删除恢复目录"
      rm -rf "$BASE"
      OK "[OK] 已清理：$BASE"
    fi
    exit 1
  fi
}

main "$@"
