import Cocoa
import FlutterMacOS

@main
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
