#!/usr/bin/env bash
# macOS Release 构建并覆盖安装到固定位置。
# Debug/Release 是正常的构建输出；正式安装只使用 ~/Applications 下的固定路径。
# 本脚本保证替换前旧实例退出；日常启动由原生入口协调跨路径单实例。

set -euo pipefail

APP_NAME="xiaoan_tsl"
BUNDLE_ID="com.jbk.xiaoantsl"
cd "$(dirname "$0")/.."
BUILD_APP="build/macos/Build/Products/Release/${APP_NAME}.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="${INSTALL_DIR}/${APP_NAME}.app"
LOCK_DIR="${INSTALL_DIR}/.${APP_NAME}-install.lock"
STAGING_DIR=""

# 只清理由本次安装创建的临时目录；异常退出也不会删除固定安装路径。
cleanup() {
  if [[ -n "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
  rmdir "$LOCK_DIR"
}

mkdir -p "$INSTALL_DIR"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "安装锁已存在：${LOCK_DIR}。请确认没有其他安装任务后再处理。" >&2
  exit 1
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

flutter build macos --release

# 校验身份与完整签名后才接触运行实例，构建或复制失败时保留旧安装。
validate_app() {
  local app="$1"
  if [[ -L "$app" || ! -d "$app" ]] ||
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" != "$BUNDLE_ID" ]]; then
    echo "应用路径或包名不符合预期：$app" >&2
    return 1
  fi
  codesign --verify --deep --strict "$app"
}

validate_app "$BUILD_APP"
if [[ -e "$INSTALL_APP" || -L "$INSTALL_APP" ]]; then
  validate_app "$INSTALL_APP"
fi
STAGING_DIR="$(mktemp -d "${INSTALL_DIR}/.${APP_NAME}-install.XXXXXX")"
STAGED_APP="$STAGING_DIR/${APP_NAME}.app"
ditto "$BUILD_APP" "$STAGED_APP"
validate_app "$STAGED_APP"

# AppKit 枚举所有同包名实例，不向可能尚未运行的应用发送 AppleScript quit。
# terminate 只代表已发送请求；必须推进主 RunLoop，等待实际退出再交换目录。
cat > "$STAGING_DIR/install.swift" <<'SWIFT'
import AppKit
import Darwin

// 安装失败时保留原始路径，并输出可定位的错误。
func fail(_ message: String) -> Never {
  fputs("\(message)\n", stderr)
  exit(1)
}

let staged = CommandLine.arguments[1]
let installed = CommandLine.arguments[2]
let bundleID = CommandLine.arguments[3]
let deadline = ProcessInfo.processInfo.systemUptime + 15
var requested: Set<pid_t> = []
while true {
  let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { !$0.isTerminated }
  if running.isEmpty { break }
  for app in running where requested.insert(app.processIdentifier).inserted {
    print("等待应用退出：PID \(app.processIdentifier)，\(app.bundleURL?.path ?? "未知路径")")
    app.terminate()
  }
  if ProcessInfo.processInfo.systemUptime >= deadline {
    fail("应用在 15 秒内未退出，保留旧安装。请结束调试或正常退出后重试。")
  }
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
}

// 暂存目录与目标在同一文件系统；交换失败不会先移除旧包。
let flags = FileManager.default.fileExists(atPath: installed) ? UInt32(RENAME_SWAP) : UInt32(RENAME_EXCL)
if renamex_np(staged, installed, flags) != 0 {
  fail("原子安装失败：\(String(cString: strerror(errno)))；原安装保持不变。")
}
SWIFT
xcrun swift "$STAGING_DIR/install.swift" "$STAGED_APP" "$INSTALL_APP" "$BUNDLE_ID"

echo "已安装到：$INSTALL_APP"
# 显式指定完整路径，避免 Launch Services 按包名选择 Debug 构建。
open "$INSTALL_APP"
