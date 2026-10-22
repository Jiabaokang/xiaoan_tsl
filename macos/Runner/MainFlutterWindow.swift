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

      overlayPanel = panel
      overlayView = view
    }

    guard let panel = overlayPanel else { return }
    // 复用面板时重新安装监听，宿主与系统 sheet 点击由面板判定豁免。
    panel.installClickOutsideMonitor { [weak self] in
      self?.desktopBridge?.triggerDismissScreenshot()
    }

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
    panel.makeFirstResponder(overlayView)
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
      stage = .loading(localized("正在截取屏幕…", "Capturing screen…"))
      canRetry = false
      canConfigure = false
    case "ocr":
      stage = .loading(localized("正在识别文字…", "Recognizing text…"))
      canRetry = false
      canConfigure = false
    case "preparingTranslation":
      stage = .preparingTranslation
      canRetry = false
      canConfigure = false
    case "translating":
      stage = .loading(localized("正在翻译…", "Translating…"))
      canRetry = false
      canConfigure = false
    case "needsConfirm":
      if confirmRequired {
        stage = .needsConfirm
      } else {
        stage = .loading(localized("正在判断语言…", "Detecting language…"))
      }
      canRetry = false
      canConfigure = false
    case "done":
      stage = .done
      canRetry = false
      canConfigure = false
    case "failed":
      let message = failureMessage(for: failureName, appleErrorCode: snapshot["appleErrorCode"] as? String)
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

  // 原生文案与系统语言一致；苹果错误由稳定代码映射，不暴露 SDK 内部描述。
  private func localized(_ chinese: String, _ english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
  }

  private func failureMessage(for failure: String, appleErrorCode: String?) -> String {
    switch failure {
    case "apple": return AppleTranslationBridge.message(appleErrorCode ?? "appleTranslationFailed")
    case "permissionDenied": return localized("屏幕录制权限被拒绝", "Screen recording permission denied")
    case "captureFailed": return localized("截图失败", "Screen capture failed")
    case "invalidData": return localized("截图数据无效", "Invalid screenshot data")
    case "ocrFailed": return localized("文字识别失败", "Text recognition failed")
    case "noText": return localized("未识别到文字", "No text recognized")
    case "tooLong": return localized("文字过长（超过 5000 字符）", "Text exceeds 5000 characters")
    case "missingCredentials": return localized("请先配置翻译服务", "Please configure a translation service")
    case "timeout": return localized("翻译超时", "Translation timed out")
    case "translationFailed": return localized("翻译失败", "Translation failed")
    case "unsupported": return localized("当前平台不支持", "This platform is not supported")
    default: return localized("未知错误", "Unknown error")
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
