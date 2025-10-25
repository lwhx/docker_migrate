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
    apt)    asudo apt-get update -y; asudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@";;
    dnf)    asudo dnf install -y "$@";;
    yum)    asudo yum install -y "$@";;
    zypper) asudo zypper --non-interactive install -y "$@";;
    apk)    asudo apk add --no-cache "$@";;
    *)      return 1;;
  esac
}

ensure_deps(){
  local PM; PM="$(pm_detect)"
  for pair in "curl curl" "tar tar" "jq jq" "docker docker"; do
    local bin="${pair%% *}" pkg="${pair##* }"
    if ! command -v "$bin" >/dev/null 2>&1; then
      [[ "$PM" == "none" ]] && { RED "[ERR] 缺少 $bin，请手动安装"; exit 1; }
      YEL "[INFO] 安装依赖：$bin"
      pm_install "$PM" "$pkg"
    fi
  done
  # 尝试启动 docker
  if ! docker info >/dev/null 2>&1; then
    YEL "[INFO] 启动 Docker 服务..."
    if command -v systemctl >/dev/null 2>&1; then asudo systemctl enable --now docker || true; fi
    if ! docker info >/dev/null 2>&1 && command -v service >/dev/null 2>&1; then asudo service docker start || true; fi
    docker info >/dev/null 2>&1 || { RED "[ERR] Docker 未能启动"; exit 1; }
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
  local TGZ="${BASE}/bundle.tar.gz"
  local OUTDIR="${BASE}/${RID}"

  BLUE "[INFO] 下载：$URL"
  if ! curl -fL --progress-bar "$URL" -o "$TGZ"; then
    RED "[ERR] 下载失败：$URL"
    exit 1
  fi
  OK "[OK] 保存路径：$TGZ"
  BLUE "[INFO] 大小：$(du -h "$TGZ" | awk '{print $1}')"

  BLUE "[INFO] 解压到：$OUTDIR"
  mkdir -p "$OUTDIR"
  tar -xzf "$TGZ" -C "$OUTDIR"

  # 进入真正的 bundle 目录（可能是 <RID>/RID 或 <RID>/）
  local BUNDLE_DIR
  if [[ -d "${OUTDIR}/${RID}" && -f "${OUTDIR}/${RID}/restore.sh" ]]; then
    BUNDLE_DIR="${OUTDIR}/${RID}"
  else
    # 兜底：找含 restore.sh 的第一层目录
    BUNDLE_DIR="$(find "$OUTDIR" -maxdepth 2 -type f -name restore.sh -printf '%h\n' | head -n1 || true)"
  fi
  [[ -n "$BUNDLE_DIR" && -f "${BUNDLE_DIR}/restore.sh" ]] || { RED "[ERR] 未找到 restore.sh，解压内容异常：$OUTDIR"; exit 1; }

  BLUE "[INFO] 执行恢复脚本：${BUNDLE_DIR}/restore.sh"
  set +e
  bash "${BUNDLE_DIR}/restore.sh"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    OK "[OK] 恢复完成！当前容器："
    docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}"
    # 自动清理（默认：删tgz+解压目录）
    if [[ "${RESTORE_KEEP:-0}" == "1" ]]; then
      YEL "[INFO] 已按 RESTORE_KEEP=1 保留文件：$TGZ 与 $OUTDIR"
    else
      rm -rf "$TGZ" "$OUTDIR" 2>/dev/null || true
      OK "[OK] 已清理下载文件与临时目录"
    fi
    exit 0
  else
    RED "[ERR] 恢复脚本返回非零：$rc"
    YEL "[INFO] 为便于排查，保留文件：$TGZ 与 $OUTDIR"
    if [[ "${RESTORE_CLEAN_ALL:-0}" == "1" ]]; then
      YEL "[WARN] RESTORE_CLEAN_ALL=1：仍将强制删除文件"
      rm -rf "$TGZ" "$OUTDIR" 2>/dev/null || true
      OK "[OK] 已清理下载文件与临时目录"
    fi
    exit "$rc"
  fi
}

main "$@"
