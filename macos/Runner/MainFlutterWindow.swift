import Cocoa
import FlutterMacOS

// 主窗口管理业务引擎；独立结果引擎只展示状态，不打开数据库或注册快捷键。
class MainFlutterWindow: NSWindow, NSWindowDelegate {
  // 桌面通道桥生命周期与主窗口一致；AppDelegate 菜单动作经由此引用。
  var desktopBridge: MacDesktopBridge?

  // 关闭结果时仅隐藏窗口，后续截图复用展示引擎。
  private(set) var resultWindow: NSWindow?
  private var resultEngine: FlutterEngine?
  private var resultChannel: FlutterMethodChannel?
  private var resultSnapshot: [String: Any]?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let bridge = MacDesktopBridge().register(with: flutterViewController)
    bridge.mainWindow = self
    desktopBridge = bridge

    // 关闭窗口时隐藏而非销毁 Flutter 引擎。
    self.delegate = self

    super.awakeFromNib()
  }

  // 在独立结果窗口中展示主引擎的会话；主页的尺寸、位置和导航保持原状。
  func showResultWindow(displayId: CGDirectDisplayID, selection: CGRect) {
    if resultWindow == nil {
      let engine = FlutterEngine(name: "screenshot_result", project: nil, allowHeadlessExecution: true)
      let channel = FlutterMethodChannel(name: "xiaoan_tsl/screenshot_window",
                                        binaryMessenger: engine.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { result(nil); return }
        if call.method == "ready" {
          result(self.resultSnapshot)
          return
        }
        self.desktopBridge?.triggerResultAction(call.method)
        result(nil)
      }
      guard engine.run(withEntrypoint: "screenshotWindowMain") else {
        channel.setMethodCallHandler(nil)
        engine.shutDownEngine()
        return
      }
      resultEngine = engine
      resultChannel = channel
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      window.title = "小安翻译 · 截图翻译"
      window.contentMinSize = NSSize(width: 360, height: 300)
      window.contentViewController = FlutterViewController(
        engine: engine, nibName: nil, bundle: nil
      )
      window.delegate = self
      resultWindow = window
    }
    guard let resultWindow else { return }
    let screens = NSScreen.screens
    let screen = screens.first(where: { candidate in
      guard let number = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
      else { return false }
      return number.uint32Value == displayId
    }) ?? screens.first
    guard let screen else { return }
    // 结果窗口默认放在选区右侧；放不下时移到选区下方。
    let visible = screen.visibleFrame
    let resultSize = NSSize(width: min(480, visible.width), height: min(560, visible.height))
    var origin = NSPoint(
      x: selection.maxX + 16,
      y: selection.minY
    )
    if origin.x + resultSize.width > visible.maxX {
      origin.x = max(visible.minX, selection.minX - resultSize.width - 16)
    }
    if origin.x + resultSize.width > visible.maxX {
      origin.x = visible.maxX - resultSize.width
    }
    if origin.y + resultSize.height > visible.maxY {
      origin.y = selection.minY - resultSize.height
    }
    if origin.y < visible.minY {
      origin.y = visible.minY
    }
    origin.x = min(max(origin.x, visible.minX), visible.maxX - resultSize.width)
    origin.y = min(max(origin.y, visible.minY), visible.maxY - resultSize.height)
    if selection.isEmpty {
      origin = NSPoint(x: visible.midX - resultSize.width / 2,
                       y: visible.midY - resultSize.height / 2)
    }
    if resultWindow.isMiniaturized { resultWindow.deminiaturize(nil) }
    resultWindow.setFrame(CGRect(origin: origin, size: resultSize), display: true, animate: false)
    resultWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // 保存最新快照供首次握手读取，后续更新不重复创建窗口或调用翻译服务。
  func updateResult(_ snapshot: [String: Any]) {
    let previousStage = resultSnapshot?["stage"] as? String
    resultSnapshot = snapshot
    resultChannel?.invokeMethod("update", arguments: snapshot)
    if snapshot["stage"] as? String == "idle" {
      if previousStage != nil && previousStage != "idle" { closeResultWindow() }
    } else if snapshot["stage"] as? String == "failed" && resultWindow?.isVisible != true {
      showResultWindow(displayId: CGMainDisplayID(), selection: .zero)
    }
  }

  // 明确退出时释放展示引擎；日常关窗仅隐藏，保持主引擎及数据库会话。
  func shutdownResultWindow() {
    resultChannel?.setMethodCallHandler(nil)
    resultEngine?.shutDownEngine()
  }

  // Dock、菜单与配置入口统一恢复主窗口，不改变截图结果或编辑内容。
  func restoreMainWindow() {
    if isMiniaturized { deminiaturize(nil) }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // 框选前隐藏两个窗口，避免把自己的主页或旧译文截入快照。
  func hideWindowsForCapture() {
    orderOut(nil)
    resultWindow?.orderOut(nil)
  }

  // 页面关闭或 Esc 结束会话后，恢复主窗口；Flutter 视图继续复用。
  func closeResultWindow() {
    resultWindow?.orderOut(nil)
    restoreMainWindow()
  }

  // 关闭时隐藏窗口，保留 Flutter 引擎与数据库会话。
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === resultWindow {
      closeResultWindow()
      desktopBridge?.triggerDismissScreenshot()
    } else {
      orderOut(nil)
    }
    return false
  }
}
