import Cocoa
import FlutterMacOS

// 主窗口管理业务引擎；原位覆盖面板替代独立结果引擎，不再启动第二个 Flutter Engine。
class MainFlutterWindow: NSWindow, NSWindowDelegate {
  // 桌面通道桥生命周期与主窗口一致；AppDelegate 菜单动作经由此引用。
  var desktopBridge: MacDesktopBridge?

  // 原位覆盖面板：在截图选区位置显示翻译结果。
  private(set) var overlayPanel: OverlayResultPanel?
  private var overlayView: OverlayResultView?

  // 当前覆盖面板所在的选区和显示器，用于重新定位。
  private var overlaySelection: CGRect = .zero
  private var overlayDisplayId: CGDirectDisplayID = 0

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

  // 在截图选区的精确位置创建或复用覆盖面板。
  func showOverlayPanel(displayId: CGDirectDisplayID, selection: CGRect) {
    overlaySelection = selection
    overlayDisplayId = displayId

    if overlayPanel == nil {
      let panel = OverlayResultPanel(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.level = .floating
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.isReleasedWhenClosed = false

      let view = OverlayResultView(frame: .zero)
      view.hostPanel = panel
      view.onAction = { [weak self] action in
        self?.handleOverlayAction(action)
      }
      panel.contentView = view
      panel.delegate = self

      // 面板外点击关闭。
      panel.installClickOutsideMonitor { [weak self] in
        self?.desktopBridge?.triggerDismissScreenshot()
      }

      overlayPanel = panel
      overlayView = view
    }

    guard let panel = overlayPanel else { return }

    // 将选区坐标映射到屏幕坐标。
    let screens = NSScreen.screens
    let screen = screens.first(where: { candidate in
      guard let number = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
      else { return false }
      return number.uint32Value == displayId
    }) ?? screens.first
    guard let screen else { return }

    // 选区使用 Cocoa 左下原点坐标，NSPanel frame 也是。
    let panelFrame: CGRect
    if selection.isEmpty {
      // 选区为空时居中显示。
      let visible = screen.visibleFrame
      let size = NSSize(width: 320, height: 200)
      panelFrame = CGRect(
        x: visible.midX - size.width / 2,
        y: visible.midY - size.height / 2,
        width: size.width, height: size.height
      )
    } else {
      // 精确匹配选区位置和大小，但保证最小尺寸。
      let minWidth: CGFloat = 200
      let minHeight: CGFloat = 80
      let width = max(selection.width, minWidth)
      let height = max(selection.height, minHeight)
      // 如果选区太小，以选区中心为基准扩展。
      let x: CGFloat
      let y: CGFloat
      if selection.width < minWidth {
        x = selection.midX - minWidth / 2
      } else {
        x = selection.minX
      }
      if selection.height < minHeight {
        y = selection.midY - minHeight / 2
      } else {
        y = selection.minY
      }
      panelFrame = CGRect(x: x, y: y, width: width, height: height)
    }

    if panel.isMiniaturized { panel.deminiaturize(nil) }
    panel.setFrame(panelFrame, display: true, animate: false)
    panel.alphaValue = 1.0
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // 解析 Dart 推送的状态快照并更新覆盖面板。
  func updateOverlayResult(_ snapshot: [String: Any]) {
    let stageName = snapshot["stage"] as? String ?? "idle"
    let failureName = snapshot["failure"] as? String ?? "none"

    // idle 状态时关闭面板。
    if stageName == "idle" {
      closeOverlayPanel()
      return
    }

    let recognizedText = snapshot["recognizedText"] as? String
    let translatedText = snapshot["translatedText"] as? String
    let confirmRequired = snapshot["confirmRequired"] as? Bool ?? false
    let historySaveFailed = snapshot["historySaveFailed"] as? Bool ?? false

    let stage: OverlayStage
    let canRetry: Bool
    let canConfigure: Bool

    switch stageName {
    case "capturing":
      stage = .loading("正在截取屏幕…")
      canRetry = false
      canConfigure = false
    case "ocr":
      stage = .loading("正在识别文字…")
      canRetry = false
      canConfigure = false
    case "translating":
      stage = .loading("正在翻译…")
      canRetry = false
      canConfigure = false
    case "needsConfirm":
      if confirmRequired {
        stage = .needsConfirm
      } else {
        stage = .loading("正在判断语言…")
      }
      canRetry = false
      canConfigure = false
    case "done":
      stage = .done
      canRetry = false
      canConfigure = false
    case "failed":
      let message = failureMessage(for: failureName)
      stage = .failed(message)
      canRetry = recognizedText != nil && !recognizedText!.isEmpty && failureName != "missingCredentials"
      canConfigure = failureName == "missingCredentials"
    default:
      return
    }

    let overlaySnapshot = OverlaySnapshot(
      stage: stage,
      recognizedText: recognizedText,
      translatedText: translatedText,
      canRetry: canRetry,
      canConfigure: canConfigure,
      historySaveFailed: historySaveFailed
    )

    // 失败状态且面板不可见时，重新显示面板。
    if stageName == "failed", overlayPanel?.isVisible != true {
      showOverlayPanel(displayId: overlayDisplayId.nonZero ?? CGMainDisplayID(), selection: overlaySelection)
    }

    overlayView?.update(with: overlaySnapshot)
  }

  // 将失败代码映射为用户可读的中文提示。
  private func failureMessage(for failure: String) -> String {
    switch failure {
    case "permissionDenied": return "屏幕录制权限被拒绝"
    case "captureFailed": return "截图失败"
    case "invalidData": return "截图数据无效"
    case "ocrFailed": return "文字识别失败"
    case "noText": return "未识别到文字"
    case "tooLong": return "文字过长（超过 5000 字符）"
    case "missingCredentials": return "请先配置翻译服务"
    case "timeout": return "翻译超时"
    case "translationFailed": return "翻译失败"
    case "unsupported": return "当前平台不支持"
    default: return "未知错误"
    }
  }

  // 覆盖面板工具条动作分发。
  private func handleOverlayAction(_ action: OverlayAction) {
    switch action {
    case .copy:
      break  // 复制在 OverlayResultView 内部完成
    case .reshoot:
      desktopBridge?.triggerScreenshotShortcut()
    case .dismiss:
      desktopBridge?.triggerDismissScreenshot()
    case .confirm:
      desktopBridge?.triggerResultAction("confirm")
    case .retry:
      desktopBridge?.triggerResultAction("retry")
    case .configure:
      restoreMainWindow()
      desktopBridge?.triggerResultAction("configure")
    }
  }

  // 关闭覆盖面板并恢复主窗口。
  func closeOverlayPanel() {
    overlayPanel?.removeClickOutsideMonitor()
    overlayPanel?.orderOut(nil)
    restoreMainWindow()
  }

  // 应用退出时释放面板资源。
  func shutdownOverlayPanel() {
    overlayPanel?.removeClickOutsideMonitor()
    overlayPanel?.orderOut(nil)
    overlayPanel = nil
    overlayView = nil
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
    overlayPanel?.orderOut(nil)
  }

  // 关闭时隐藏窗口，保留 Flutter 引擎与数据库会话。
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === overlayPanel {
      closeOverlayPanel()
      desktopBridge?.triggerDismissScreenshot()
    } else {
      orderOut(nil)
    }
    return false
  }
}

// CGDirectDisplayID 的非零便捷属性。
private extension CGDirectDisplayID {
  var nonZero: CGDirectDisplayID? { self == 0 ? nil : self }
}
