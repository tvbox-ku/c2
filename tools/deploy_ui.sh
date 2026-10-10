#!/bin/bash
# ─────────────────────────────────────────────────────────────
# deploy_ui.sh — 部署自编译 UI 到 C2 设备
#
# 用法:
#   ./deploy_ui.sh <C2_IP> [build|deploy|restart|all]
#
#   build   — 只在设备上编译 (默认)
#   deploy  — 只推送源码到设备
#   restart — 只重启 UI
#   all     — deploy + build + restart
# ─────────────────────────────────────────────────────────────

set -e

C2_IP="${1:?用法: ./deploy_ui.sh <C2_IP> [build|deploy|restart|all]}"
ACTION="${2:-all}"
C2_USER="comma"
C2_PATH="/data/openpilot"
LOCAL_UI="selfdrive/ui_src"
LOCAL_SCONSTRUCT="SConstruct"

echo "══════════════════════════════════════════════════"
echo "  C2 设备: ${C2_USER}@${C2_IP}"
echo "  远程路径: ${C2_PATH}"
echo "  操作: ${ACTION}"
echo "══════════════════════════════════════════════════"
echo ""

# ── deploy: 推送源码 ──
deploy() {
  echo "[1/3] 推送 UI 源码到设备..."
  ssh "${C2_USER}@${C2_IP}" "mkdir -p ${C2_PATH}/selfdrive/ui_new"

  # 推送 UI 源码 (排除编译产物)
  scp -r ${LOCAL_UI}/* "${C2_USER}@${C2_IP}:${C2_PATH}/selfdrive/ui_new/"

  # 推送 SConstruct
  scp ${LOCAL_SCONSTRUCT} "${C2_USER}@${C2_IP}:${C2_PATH}/SConstruct.custom"

  # 备份旧 UI, 替换为新源码
  ssh "${C2_USER}@${C2_IP}" bash -s << 'REMOTE'
    cd /data/openpilot
    # 备份原始 UI
    if [ ! -d selfdrive/ui_backup ]; then
      cp -a selfdrive/ui selfdrive/ui_backup
      echo "  → 原始 UI 已备份到 selfdrive/ui_backup/"
    fi
    # 替换 UI 源码
    rm -rf selfdrive/ui
    mv selfdrive/ui_new selfdrive/ui
    echo "  → UI 源码已替换"
REMOTE
  echo "[1/3] 完成"
  echo ""
}

# ── build: 在设备上编译 ──
build() {
  echo "[2/3] 在设备上编译 UI..."
  ssh "${C2_USER}@${C2_IP}" bash -s << 'REMOTE'
    cd /data/openpilot
    export PYTHONPATH=/data/openpilot
    echo "  → 检查构建环境..."
    which scons >/dev/null 2>&1 && echo "  → scons: OK" || { echo "  ✗ scons 未安装! 尝试 pip install scons"; pip install scons; }
    which g++ >/dev/null 2>&1 && echo "  → g++: OK" || echo "  ⚠ g++ 未找到 (可能需要 clang)"
    ls /system/vendor/lib64/libgui.so >/dev/null 2>&1 && echo "  → Android libs: OK" || echo "  ⚠ Android 系统库路径异常"

    echo "  → 开始编译 (仅 UI)..."
    scons -j4 selfdrive/ui/_ui 2>&1 | tail -30

    if [ -f selfdrive/ui/_ui ]; then
      echo "  → 编译成功! _ui 已生成"
    else
      echo "  ✗ 编译失败! 请检查错误信息"
      exit 1
    fi
REMOTE
  echo "[2/3] 完成"
  echo ""
}

# ── restart: 重启 UI ──
restart() {
  echo "[3/3] 重启 UI..."
  ssh "${C2_USER}@${C2_IP}" bash -s << 'REMOTE'
    cd /data/openpilot
    # 重启 UI 进程
    pkill -f "_ui" 2>/dev/null || true
    sleep 1
    # 通过 manager 重启
    pm restart com.comma.ai.frontend 2>/dev/null || (
      echo "  → 手动启动 UI..."
      cd /data/openpilot/selfdrive/ui
      nohup ./ui > /dev/null 2>&1 &
    )
    echo "  → UI 已重启"
REMOTE
  echo "[3/3] 完成"
  echo ""
}

# ── 执行 ──
case "$ACTION" in
  deploy)  deploy ;;
  build)   build ;;
  restart) restart ;;
  all)     deploy; build; restart ;;
  *)       echo "未知操作: $ACTION"; echo "可用: deploy|build|restart|all"; exit 1 ;;
esac

echo ""
echo "══════════════════════════════════════════════════"
echo "  完成! 在 C2 屏幕上检查设置页面"
echo "══════════════════════════════════════════════════"
