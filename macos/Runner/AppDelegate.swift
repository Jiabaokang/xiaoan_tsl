import Cocoa
import FlutterMacOS
import Darwin

// 持有内核文件锁；启动仲裁发生在 nib 和 Flutter 引擎创建之前。
final class MacAppLaunchLease {
  // 锁内记录的进程与编译模式，不根据 Debug/Release 目录名猜测身份。
  struct Owner: Codable {
    let processID: pid_t
    let isDebug: Bool
  }

  // 重复启动只唤回现有实例；Debug 通过协作通知请求 Release 自行退出。
  enum Action: Equatable {
    case activate
    case yieldToDebug
  }

  // 始终保留同一 inode；不能删除锁文件，否则等待者可能锁到不同文件。
  private let file: FileHandle

  // 创建锁所在目录，拒绝最终锁路径为符号链接。
  private init(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }

  // 只有持锁者才能启动；退出请求发出后仍须等待内核锁真正释放。
  static func acquire(
    at url: URL,
    isDebug: Bool,
    timeout: TimeInterval = 15,
    peerAction: (Owner, Action) -> Bool
  ) throws -> MacAppLaunchLease? {
    let lease = try MacAppLaunchLease(at: url)
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while true {
      if flock(lease.file.fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
        let owner = Owner(processID: getpid(), isDebug: isDebug)
        try lease.file.truncate(atOffset: 0)
        try lease.file.seek(toOffset: 0)
        try lease.file.write(contentsOf: JSONEncoder().encode(owner))
        return lease
      }
      guard errno == EWOULDBLOCK || errno == EAGAIN else {
        throw POSIXError(.init(rawValue: errno) ?? .EIO)
      }
      try lease.file.seek(toOffset: 0)
      if let data = try lease.file.read(upToCount: 1024),
         let owner = try? JSONDecoder().decode(Owner.self, from: data) {
        let action: Action = isDebug && !owner.isDebug ? .yieldToDebug : .activate
        if peerAction(owner, action), action == .activate { return nil }
      }
      guard ProcessInfo.processInfo.systemUptime < deadline else {
        throw NSError(domain: "MacAppLaunchLease", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "已有小安翻译实例未响应。请正常退出旧实例后重试；未启动第二个翻译引擎。",
        ])
      }
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }
}

// 自定义入口先完成单实例仲裁，再交给 AppKit 加载原有 MainMenu nib。
@main
enum XiaoanApplication {
  // 通知不携带 userInfo，满足 App Sandbox 的跨进程通知约束。
  private static let activateName = Notification.Name("com.jbk.xiaoantsl.activateMainWindow")
  private static let takeoverName = Notification.Name("com.jbk.xiaoantsl.yieldToDebug")

  // Debug 优先于 Release；进程锁保持到 AppKit 主循环结束。
  static func main() {
    #if DEBUG
    let isDebug = true
    #else
    let isDebug = false
    #endif
    let center = DistributedNotificationCenter.default()
    let activation = center.addObserver(forName: activateName, object: String(getpid()), queue: .main) { _ in
      (NSApp.delegate as? AppDelegate)?.restoreMainWindow()
    }
    let takeover = center.addObserver(forName: takeoverName, object: String(getpid()), queue: .main) { _ in
      if !isDebug { NSApp.terminate(nil) }
    }
    defer {
      center.removeObserver(activation)
      center.removeObserver(takeover)
    }
    do {
      let bundleID = Bundle.main.bundleIdentifier ?? "com.jbk.xiaoantsl"
      let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
      let url = support.appendingPathComponent(bundleID).appendingPathComponent("instance.lock")
      guard let lease = try MacAppLaunchLease.acquire(at: url, isDebug: isDebug, peerAction: { owner, action in
        guard let app = NSRunningApplication(processIdentifier: owner.processID),
              app.bundleIdentifier == bundleID, !app.isTerminated, app.isFinishedLaunching else { return false }
        let name = action == .activate ? activateName : takeoverName
        center.postNotificationName(name, object: String(owner.processID), userInfo: nil, deliverImmediately: true)
        if action == .activate { app.activate(options: [.activateAllWindows]) }
        return true
      }) else { return }
      // 首次升级时，旧二进制没有进程锁或协作通知；不能把它误判为已退出。
      let legacy = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != getpid() && !$0.isTerminated && $0.isFinishedLaunching }
      guard legacy.isEmpty else {
        throw NSError(domain: "MacAppLaunchLease", code: 2, userInfo: [
          NSLocalizedDescriptionKey: "旧版小安翻译仍在运行。首次升级请正常退出旧版，或使用安装脚本完成替换后重试。",
        ])
      }
      withExtendedLifetime(lease) {
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
      }
    } catch {
      fputs("小安翻译启动失败：\(error.localizedDescription)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }
}

// 管理桌面菜单和 Dock 唤起；关闭窗口保留应用，明确退出才销毁会话。
class AppDelegate: FlutterAppDelegate {
  // 主窗口由 nib 实例化；菜单栏动作与窗口恢复共用该引用。
  private weak var mainWindow: MainFlutterWindow?

  private var desktopBridge: MacDesktopBridge? {
    mainWindow?.desktopBridge
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 截图翻译常驻：主窗口关闭后应用继续运行。
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // 即使结果窗口仍可见，点击 Dock 图标也应打开独立主页。
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    restoreMainWindow()
    return false
  }

  // 跨路径重复启动与 Dock 点击共用主页恢复行为。
  func restoreMainWindow() {
    mainWindow?.restoreMainWindow()
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow {
      mainWindow = window
    }
    installMenuBar()
  }

  // 明确退出时注销快捷键与通道，避免残留注册。
  override func applicationWillTerminate(_ notification: Notification) {
    desktopBridge?.shutdown()
  }

  // 菜单栏：截图翻译、打开主窗口、设置、退出。
  private func installMenuBar() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu

    let titleItem = NSMenuItem()
    titleItem.title = "小安翻译"
    appMenu.addItem(titleItem)
    appMenu.addItem(.separator())

    let screenshotItem = NSMenuItem(
      title: "截图翻译",
      action: #selector(menuScreenshot(_:)),
      keyEquivalent: ""
    )
    screenshotItem.target = self
    appMenu.addItem(screenshotItem)

    let openItem = NSMenuItem(
      title: "打开主窗口",
      action: #selector(menuOpenMainWindow(_:)),
      keyEquivalent: ""
    )
    openItem.target = self
    appMenu.addItem(openItem)

    let settingsItem = NSMenuItem(
      title: "设置",
      action: #selector(menuOpenSettings(_:)),
      keyEquivalent: ","
    )
    settingsItem.target = self
    appMenu.addItem(settingsItem)

    appMenu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "退出小安翻译",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    appMenu.addItem(quitItem)

    NSApp.mainMenu = mainMenu
  }

  @objc private func menuScreenshot(_ sender: Any?) {
    // 与全局快捷键一致：仅通知 Dart，由 Dart 启动截图流程。
    desktopBridge?.triggerScreenshotShortcut()
  }

  @objc private func menuOpenMainWindow(_ sender: Any?) {
    mainWindow?.restoreMainWindow()
  }

  @objc private func menuOpenSettings(_ sender: Any?) {
    desktopBridge?.triggerOpenSettings()
  }
}
