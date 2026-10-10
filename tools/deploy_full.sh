#!/bin/bash
# ─────────────────────────────────────────────────────────────
# deploy_full.sh — 完整项目部署到 C2 设备
#
# 用法:
#   bash deploy_full.sh <C2_IP> [method] [action]
#
#   method: rsync (默认) | tar | git
#   action: push      — 只推送代码
#           build     — 只编译
#           restart   — 只重启
#           all       — push + build + restart (默认)
#
# 示例:
#   bash deploy_full.sh 192.168.1.10                    # rsync 全流程
#   bash deploy_full.sh 192.168.1.10 tar push           # tar 打包推送
#   bash deploy_full.sh 192.168.1.10 rsync build        # 只编译
# ─────────────────────────────────────────────────────────────

set -e

C2_IP="${1:?用法: bash deploy_full.sh <C2_IP> [rsync|tar|git] [push|build|restart|all]}"
METHOD="${2:-rsync}"
ACTION="${3:-all}"
C2_USER="comma"
C2_PATH="/data/openpilot"
LOCAL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 排除列表 (不需要推送到设备的文件)
EXCLUDES=(
  --exclude='.git'
  --exclude='__pycache__'
  --exclude='*.pyc'
  --exclude='.sconsign.dblite'
  --exclude='build/'
  --exclude='*.o'
  --exclude='*.so'
  --exclude='*.a'
  --exclude='selfdrive/ui/_ui'
  --exclude='selfdrive/ui/soundd/_soundd'
  --exclude='selfdrive/ui/qt/spinner'
  --exclude='selfdrive/ui/qt/text'
  --exclude='selfdrive/ui/qt/libpython_helpers.so'
  --exclude='tools/adjust_lane_offset_preview.html'
  --exclude='tools/c2_screen_preview.html'
)

echo "════════════════════════════════════════════════════════"
echo "  部署到 C2 设备: ${C2_USER}@${C2_IP}:${C2_PATH}"
echo "  方法: ${METHOD}  操作: ${ACTION}"
echo "  本地路径: ${LOCAL_DIR}"
echo "════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════
# push: 推送代码到设备
# ═══════════════════════════════════════════════════════════
push_rsync() {
  echo "[PUSH] rsync 同步..."
  rsync -avz --progress "${EXCLUDES[@]}" \
    "${LOCAL_DIR}/" "${C2_USER}@${C2_IP}:${C2_PATH}/"
  echo "[PUSH] 完成"
}

push_tar() {
  echo "[PUSH] tar 打包 + scp 传输..."
  TAR_FILE="/tmp/openpilot_deploy.tar.gz"
  echo "  → 打包中..."
  tar czf "$TAR_FILE" -C "$LOCAL_DIR" \
    --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
    --exclude='.sconsign.dblite' --exclude='build/' \
    --exclude='*.o' --exclude='*.so' --exclude='*.a' \
    --exclude='selfdrive/ui/_ui' \
    .
  SIZE=$(du -h "$TAR_FILE" | cut -f1)
  echo "  → 包大小: ${SIZE}"
  echo "  → 传输中..."
  scp "$TAR_FILE" "${C2_USER}@${C2_IP}:/tmp/"
  rm -f "$TAR_FILE"

  echo "  → 设备上解压..."
  ssh "${C2_USER}@${C2_IP}" bash -s << 'REMOTE'
    cd /data/openpilot
    # 备份当前版本 (首次部署)
    if [ ! -f /data/openpilot_backup_marker ]; then
      touch /data/openpilot_backup_marker
      echo "  → 首次部署, 无需备份"
    fi
    # 解压新代码
    tar xzf /tmp/openpilot_deploy.tar.gz -C /data/openpilot/
    rm -f /tmp/openpilot_deploy.tar.gz
    echo "  → 解压完成"
REMOTE
  echo "[PUSH] 完成"
}

push_git() {
  echo "[PUSH] git 方式..."
  echo "  ⚠ git 方式需要项目已推送到 GitHub"
  echo "  请输入 GitHub 仓库地址 (或按 Enter 跳过):"
  read -r GIT_URL
  if [ -z "$GIT_URL" ]; then
    echo "  → 跳过 git 部署"
    return
  fi
  ssh "${C2_USER}@${C2_IP}" bash -s << REMOTE
    cd /data
    if [ -d openpilot ]; then
      cd openpilot
      git remote set-url origin "$GIT_URL" 2>/dev/null || git remote add origin "$GIT_URL"
      git pull origin main || git pull origin master
    else
      git clone "$GIT_URL" openpilot
    fi
    echo "  → git 部署完成"
REMOTE
  echo "[PUSH] 完成"
}

# ═══════════════════════════════════════════════════════════
# build: 在设备上编译
# ═══════════════════════════════════════════════════════════
build() {
  echo "[BUILD] 在 C2 上编译..."
  ssh "${C2_USER}@${C2_IP}" bash -s << 'REMOTE'
    cd /data/openpilot
    export PYTHONPATH=/data/openpilot

    echo "  → 检查构建环境..."
    which scons >/dev/null 2>&1 && echo "    scons: OK" || { echo "    scons: 安装中..."; pip install scons; }
    python3 -c "import numpy" 2>/dev/null && echo "    numpy: OK" || echo "    numpy: 缺失"

    # 如果 ui_src 存在, 替换 ui 目录
    if [ -d selfdrive/ui_src ] && [ ! -d selfdrive/ui_backup ]; then
      echo "  → 替换 UI: 备份旧 UI, 启用新源码"
      mv selfdrive/ui selfdrive/ui_backup
      cp -a selfdrive/ui_src selfdrive/ui
      echo "  → UI 源码已替换"
    fi

    echo "  → 编译 UI..."
    scons -j4 selfdrive/ui/_ui 2>&1 | tail -50

    if [ -f selfdrive/ui/_ui ]; then
      echo "  ✅ UI 编译成功"
    else
      echo "  ❌ UI 编译失败"
      echo "  → 尝试编译 Python 部分确认基础环境正常..."
      scons -j4 selfdrive/manager/manager.py 2>&1 | tail -10
      exit 1
    fi
REMOTE
  echo "[BUILD] 完成"
}

# ═══════════════════════════════════════════════════════════
# restart: 重启 openpilot
# ═══════════════════════════════════════════════════════════
restart() {
  echo "[RESTART] 重启 openpilot..."
  ssh "${C2_USER}@${C2_IP}" bash -s << 'REMOTE'
    cd /data/openpilot
    # 方式1: 通过 pm 重启 (Android package manager)
    pm restart com.comma.ai.frontend 2>/dev/null && echo "  → pm restart 成功" || {
      # 方式2: kill + manager 重启
      echo "  → kill UI 进程..."
      pkill -f "selfdrive/ui/_ui" 2>/dev/null || true
      pkill -f "selfdrive/manager/manager" 2>/dev/null || true
      sleep 2
      echo "  → 重启 manager..."
      nohup python3 selfdrive/manager/manager.py > /dev/null 2>&1 &
      echo "  → manager 已启动"
    }
    sleep 2
    echo "  → openpilot 已重启"
REMOTE
  echo "[RESTART] 完成"
}

# ═══════════════════════════════════════════════════════════
# 执行
# ═══════════════════════════════════════════════════════════
case "$ACTION" in
  push)    "push_${METHOD}" ;;
  build)   build ;;
  restart) restart ;;
  all)     "push_${METHOD}"; echo ""; build; echo ""; restart ;;
  *)       echo "未知操作: $ACTION"; exit 1 ;;
esac

echo ""
echo "════════════════════════════════════════════════════════"
echo "  部署完成!"
echo "  在 C2 屏幕上检查: 设置 → VIP Panel → 余裕空间自动避让"
echo "════════════════════════════════════════════════════════"
