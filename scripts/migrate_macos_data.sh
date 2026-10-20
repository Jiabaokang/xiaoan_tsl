#!/usr/bin/env bash
# 包名从 com.example.xiaoanTsl 变更为 com.jbk.xiaoantsl 后，
# 把旧沙盒容器中的应用数据迁移到新容器。
#
# 使用前提：先用新包名运行一次应用（flutter run -d macos），
# 让系统创建新容器，随后退出应用，再执行本脚本。

set -euo pipefail

OLD_ID="com.example.xiaoanTsl"
NEW_ID="com.jbk.xiaoantsl"
OLD_CONTAINER="$HOME/Library/Containers/${OLD_ID}/Data"
NEW_CONTAINER="$HOME/Library/Containers/${NEW_ID}/Data"

if [ ! -d "$NEW_CONTAINER" ]; then
  echo "未发现新容器。请先用新包名运行一次应用：flutter run -d macos"
  exit 1
fi

# 确保应用已退出，避免迁移时数据库被占用。
osascript -e "tell application id \"${NEW_ID}\" to quit" 2>/dev/null || true

# 迁移 Documents（xiaoan.db 数据库等用户数据）；-n 表示不覆盖新容器已有文件。
if [ -d "$OLD_CONTAINER/Documents" ]; then
  mkdir -p "$NEW_CONTAINER/Documents"
  cp -Rn "$OLD_CONTAINER/Documents/." "$NEW_CONTAINER/Documents/"
  echo "Documents 数据已迁移。"
fi

echo "迁移完成。旧容器保留在：$HOME/Library/Containers/${OLD_ID}"
echo "确认数据无误后，可手动删除该旧容器。"
echo "注意：存储在钥匙串中的密钥（如百度翻译密钥）不属于容器数据，需在应用内重新填写。"
