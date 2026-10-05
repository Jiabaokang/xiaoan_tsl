import Cocoa
import FlutterMacOS

// 主窗口承载 Flutter 引擎，并在后台截图完成后恢复显示识别和翻译结果。
class MainFlutterWindow: NSWindow, NSWindowDelegate {
  // 桌面通道桥生命周期与主窗口一致；AppDelegate 菜单动作经由此引用。
  var desktopBridge: MacDesktopBridge?

  // 正常窗口的 frame/style，进入结果窗口模式前保存。
  private var normalFrame: NSRect?
  private var normalStyleMask: NSWindow.StyleMask?

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

  // 记录正常窗口 frame/style，并切换到靠近选区的紧凑结果窗口（单一 Flutter 引擎）。
  func showResultWindow(displayId: CGDirectDisplayID, selection: CGRect) {
    if normalFrame == nil {
      normalFrame = frame
      normalStyleMask = styleMask
    }
    let screens = NSScreen.screens
    let screen = screens.first(where: { candidate in
      guard let number = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
      else { return false }
      return number.uint32Value == displayId
    }) ?? screens.first
    guard let screen else { return }
    // 结果窗口默认放在选区右侧；放不下时移到选区下方。
    let resultSize = NSSize(width: 480, height: 560)
    let visible = screen.visibleFrame
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
    let resultFrame = CGRect(origin: origin, size: resultSize)
    if isMiniaturized { deminiaturize(nil) }
    setFrame(resultFrame, display: true, animate: false)
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // 恢复正常窗口 frame/style 并显示。
  func restoreMainWindow() {
    if let normalFrame {
      setFrame(normalFrame, display: true, animate: false)
    }
    normalFrame = nil
    if isMiniaturized { deminiaturize(nil) }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // 关闭时隐藏窗口，保留 Flutter 引擎与数据库会话。
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    orderOut(nil)
    return false
  }
}
