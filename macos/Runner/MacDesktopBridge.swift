import Cocoa
import Carbon.HIToolbox
import FlutterMacOS
import ScreenCaptureKit

// 无边框选区面板也必须接收键盘焦点，使后台截图时 Esc 可以取消。
final class SelectionOverlayPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

// 选区覆盖层视图：显示全屏快照，拖拽定义选区；Esc 由会话级本地监听处理。
final class SelectionOverlayView: NSView {
  // 完成回调只调用一次；rect 为左下原点 point 坐标，nil 表示取消。
  var onComplete: ((CGRect?) -> Void)?

  private let snapshot: CGImage
  private var selection: CGRect?
  private var dragStart: NSPoint?
  private var didComplete = false

  init(snapshot: CGImage) {
    self.snapshot = snapshot
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) 未实现")
  }

  override var acceptsFirstResponder: Bool { true }

  // 后台截图时首次点击直接开始拖拽，不先消耗一次点击来激活应用。
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    // 全屏快照作为背景。
    if let context = NSGraphicsContext.current?.cgContext {
      context.interpolationQuality = .high
      context.draw(snapshot, in: bounds)
    }
    guard let selection else {
      NSColor.black.withAlphaComponent(0.15).setFill()
      bounds.fill()
      let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? true
      let hint = chinese ? "拖动框选文字，松开鼠标翻译 · Esc 取消"
        : "Drag to select text, release to translate · Esc to cancel"
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      (hint as NSString).draw(in: NSRect(x: bounds.midX - 260, y: bounds.maxY - 70,
        width: 520, height: 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 18, weight: .medium),
        .foregroundColor: NSColor.white,
        .backgroundColor: NSColor.black.withAlphaComponent(0.75),
        .paragraphStyle: paragraph,
      ])
      return
    }
    // 选区外的半透明遮罩。
    NSColor.black.withAlphaComponent(0.35).setFill()
    let outside = NSBezierPath()
    outside.appendRect(CGRect(x: bounds.minX, y: selection.maxY,
                              width: bounds.width, height: bounds.maxY - selection.maxY))
    outside.appendRect(CGRect(x: bounds.minX, y: selection.minY,
                              width: selection.minX, height: selection.height))
    outside.appendRect(CGRect(x: selection.maxX, y: selection.minY,
                              width: bounds.maxX - selection.maxX, height: selection.height))
    outside.appendRect(CGRect(x: bounds.minX, y: bounds.minY,
                              width: bounds.width, height: selection.minY))
    outside.fill()
    // 选区边框。
    NSColor.controlAccentColor.setStroke()
    let border = NSBezierPath(rect: selection)
    border.lineWidth = 1.5
    border.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    dragStart = convert(event.locationInWindow, from: nil)
    selection = CGRect(origin: dragStart!, size: .zero)
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard let dragStart else { return }
    let current = convert(event.locationInWindow, from: nil)
    selection = CGRect(
      x: min(dragStart.x, current.x),
      y: min(dragStart.y, current.y),
      width: abs(current.x - dragStart.x),
      height: abs(current.y - dragStart.y)
    )
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    guard let selection, !didComplete else { return }
    didComplete = true
    // 极小或空选区视为取消，不等同失败。
    if selection.width < 2 || selection.height < 2 {
      onComplete?(nil)
    } else {
      onComplete?(selection)
    }
  }
}

// 桌面通道桥：截图选区、OCR、语言识别、全局快捷键、事件通知与结果窗口定位。
final class MacDesktopBridge: NSObject {
  private static let channelName = "xiaoan_tsl/macos_desktop"
  private static let eventChannelName = "xiaoan_tsl/macos_desktop_events"
  private static let hotKeySignature: OSType = 0x58414E53 // "XANS"

  private let coordinator = ScreenCaptureCoordinator()
  private var overlayPanels: [NSPanel] = []
  private var overlayViews: [SelectionOverlayView] = []
  private var escMonitor: Any?
  private var completionPending: ((CaptureRegionPayload?, Bool) -> Void)?

  // 取消预取快照中的旧请求，避免重复快捷键触发后出现过期选区窗口。
  private var captureGeneration = 0

  // 结果窗口定位与主窗口恢复委托给主窗口。
  weak var mainWindow: MainFlutterWindow?

  // 全局快捷键状态。
  private var hotKeyRef: EventHotKeyRef?
  private var hotKeyID: UInt32 = 0
  private var nextHotKeyID: UInt32 = 1
  private var activeShortcut: String = ""
  private var eventSink: FlutterEventSink?

  private let methodCapture = "captureRegion"
  private let methodRecognize = "recognizeText"
  private let methodIdentify = "identifyLanguage"
  private let methodShowResult = "showResultWindow"
  private let methodCancel = "cancelCapture"
  private let methodUpdateShortcut = "updateShortcut"

  @discardableResult
  func register(with controller: FlutterViewController) -> MacDesktopBridge {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    let eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    eventChannel.setStreamHandler(self)
    installHotKeyHandler()
    return self
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case methodCapture:
      let requestId = arguments["requestId"] as? String ?? ""
      Task { await startCapture(requestId: requestId, result: result) }
    case methodRecognize:
      let requestId = arguments["requestId"] as? String ?? ""
      let png = (arguments["png"] as? FlutterStandardTypedData)?.data ?? Data()
      Task { await recognize(requestId: requestId, pngData: png, result: result) }
    case methodIdentify:
      let text = arguments["text"] as? String ?? ""
      result(coordinator.identifyLanguage(of: text))
    case methodShowResult:
      let displayId = arguments["displayId"] as? UInt32 ?? 0
      let selection = CGRect(
        x: arguments["x"] as? Double ?? 0,
        y: arguments["y"] as? Double ?? 0,
        width: arguments["width"] as? Double ?? 0,
        height: arguments["height"] as? Double ?? 0
      )
      mainWindow?.showOverlayPanel(displayId: displayId, selection: selection)
      result(nil)
    case methodCancel:
      cancelCapture()
      result(nil)
    case "updateResult":
      mainWindow?.updateOverlayResult(arguments)
      result(nil)
    case methodUpdateShortcut:
      let shortcut = arguments["shortcut"] as? String ?? ""
      do {
        try updateShortcut(shortcut)
        result(nil)
      } catch let error as ScreenshotError {
        result(FlutterError(code: error.code, message: error.message, details: nil))
      } catch {
        result(FlutterError(code: "shortcutConflict", message: "快捷键注册失败", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 全局快捷键

  // 解析 “Control+Option+T” 为 Carbon keyCode 与修饰键；纯函数便于单测。
  static func parseShortcut(_ shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? {
    let parts = shortcut.split(separator: "+").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    var modifiers: UInt32 = 0
    var keyPart: String?
    for part in parts {
      switch part {
      case "Control": modifiers |= UInt32(controlKey)
      case "Option": modifiers |= UInt32(optionKey)
      case "Command": modifiers |= UInt32(cmdKey)
      case "Shift": modifiers |= UInt32(shiftKey)
      default:
        guard keyPart == nil else { return nil }
        keyPart = part
      }
    }
    guard let keyPart, let keyCode = keyCode(for: keyPart) else { return nil }
    return (keyCode, modifiers)
  }

  // 单个可见字符映射为 QWERTY 物理键码（Carbon 全局快捷键使用物理位置）。
  static func keyCode(for key: String) -> UInt32? {
    let map: [Character: UInt32] = [
      "A": UInt32(kVK_ANSI_A), "S": UInt32(kVK_ANSI_S), "D": UInt32(kVK_ANSI_D),
      "F": UInt32(kVK_ANSI_F), "H": UInt32(kVK_ANSI_H), "G": UInt32(kVK_ANSI_G),
      "Z": UInt32(kVK_ANSI_Z), "X": UInt32(kVK_ANSI_X), "C": UInt32(kVK_ANSI_C),
      "V": UInt32(kVK_ANSI_V), "B": UInt32(kVK_ANSI_B), "Q": UInt32(kVK_ANSI_Q),
      "W": UInt32(kVK_ANSI_W), "E": UInt32(kVK_ANSI_E), "R": UInt32(kVK_ANSI_R),
      "Y": UInt32(kVK_ANSI_Y), "T": UInt32(kVK_ANSI_T), "1": UInt32(kVK_ANSI_1),
      "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4),
      "6": UInt32(kVK_ANSI_6), "5": UInt32(kVK_ANSI_5), "=": UInt32(kVK_ANSI_Equal),
      "9": UInt32(kVK_ANSI_9), "7": UInt32(kVK_ANSI_7), "-": UInt32(kVK_ANSI_Minus),
      "8": UInt32(kVK_ANSI_8), "0": UInt32(kVK_ANSI_0), "]": UInt32(kVK_ANSI_RightBracket),
      "O": UInt32(kVK_ANSI_O), "U": UInt32(kVK_ANSI_U), "[": UInt32(kVK_ANSI_LeftBracket),
      "I": UInt32(kVK_ANSI_I), "P": UInt32(kVK_ANSI_P), "L": UInt32(kVK_ANSI_L),
      "J": UInt32(kVK_ANSI_J), "'": UInt32(kVK_ANSI_Quote), "K": UInt32(kVK_ANSI_K),
      ";": UInt32(kVK_ANSI_Semicolon), "\\": UInt32(kVK_ANSI_Backslash),
      ",": UInt32(kVK_ANSI_Comma), "/": UInt32(kVK_ANSI_Slash),
      "N": UInt32(kVK_ANSI_N), "M": UInt32(kVK_ANSI_M),
      ".": UInt32(kVK_ANSI_Period), "`": UInt32(kVK_ANSI_Grave),
    ]
    guard key.count == 1 else { return nil }
    return map[Character(key.uppercased())]
  }

  // 注册新键成功后才移除旧键；失败保留旧注册；空字符串表示关闭快捷键。
  func updateShortcut(_ shortcut: String) throws {
    guard shortcut != activeShortcut else { return }
    if shortcut.isEmpty {
      if let old = hotKeyRef { UnregisterEventHotKey(old) }
      hotKeyRef = nil
      activeShortcut = ""
      return
    }
    guard let parsed = Self.parseShortcut(shortcut) else {
      throw ScreenshotError.shortcutConflict("不支持的快捷键组合：\(shortcut)")
    }
    var newRef: EventHotKeyRef?
    let newID = EventHotKeyID(signature: Self.hotKeySignature, id: nextHotKeyID)
    let status = RegisterEventHotKey(
      parsed.keyCode, parsed.modifiers, newID,
      GetEventDispatcherTarget(), 0, &newRef
    )
    guard status == noErr, let newRef else {
      throw ScreenshotError.shortcutConflict("快捷键注册失败或与其他应用冲突")
    }
    if let old = hotKeyRef { UnregisterEventHotKey(old) }
    hotKeyRef = newRef
    hotKeyID = newID.id
    activeShortcut = shortcut
    nextHotKeyID += 1
  }

  private static var hotKeyHandlerRef: EventHandlerRef?

  private func installHotKeyHandler() {
    guard Self.hotKeyHandlerRef == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let userData = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
        )
        let bridge = Unmanaged<MacDesktopBridge>.fromOpaque(userData).takeUnretainedValue()
        bridge.onHotKeyPressed(id: hotKeyID.id)
        return noErr
      },
      1, &eventType, userData, &Self.hotKeyHandlerRef
    )
  }

  private func onHotKeyPressed(id: UInt32) {
    guard id == hotKeyID else { return }
    emitEvent("screenshotHotkey")
  }

  // 菜单动作与快捷键共用同一事件；仅通知 Dart，不在此处启动捕获。
  func triggerScreenshotShortcut() {
    emitEvent("screenshotHotkey")
  }

  func triggerOpenSettings() {
    mainWindow?.restoreMainWindow()
    emitEvent("openSettings")
  }

  // 系统红色关闭按钮与 Flutter 关闭按钮共用截图会话清理逻辑。
  func triggerDismissScreenshot() {
    emitEvent("dismissScreenshot")
  }

  // 展示引擎的按钮仅转发事件，业务始终在主引擎中执行。
  func triggerResultAction(_ action: String) {
    switch action {
    case "dismiss": triggerDismissScreenshot()
    case "reshoot": triggerScreenshotShortcut()
    case "confirm": emitEvent("confirmScreenshot")
    case "retry": emitEvent("retryScreenshot")
    case "configure":
      mainWindow?.restoreMainWindow()
      emitEvent("openTranslationSettings")
    default: break
    }
  }

  private func emitEvent(_ event: String) {
    eventSink?(event)
  }

  // MARK: - 捕获流程

  @MainActor
  private func startCapture(
    requestId: String,
    result: @escaping FlutterResult
  ) async {
    let generation = captureGeneration
    let restoreOnCancel = mainWindow?.isVisible == true && mainWindow?.isMiniaturized == false
    // replayd 只能检查录屏权限；首次授权必须由应用自身正式申请。
    // 返回值不用于提前拒绝截图，最终状态仍由 ScreenCaptureKit 的实际捕获结果判断。
    _ = CGRequestScreenCaptureAccess()
    // 框选前隐藏自己的进度页，快照应包含用户正在阅读的屏幕内容。
    mainWindow?.hideWindowsForCapture()
    do {
      let (payload, _) = try await selectAndCrop()
      if let payload {
        result([
          "requestId": requestId,
          "cancelled": false,
          "png": FlutterStandardTypedData(bytes: payload.pngData),
          "displayId": payload.displayId,
          "x": payload.selection.minX,
          "y": payload.selection.minY,
          "width": payload.selection.width,
          "height": payload.selection.height,
          "pixelWidth": payload.pixelWidth,
          "pixelHeight": payload.pixelHeight,
        ])
      } else {
        if restoreOnCancel, generation == captureGeneration {
          mainWindow?.makeKeyAndOrderFront(nil)
        }
        result(["requestId": requestId, "cancelled": true])
      }
    } catch let error as ScreenshotError {
      mainWindow?.restoreMainWindow()
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      mainWindow?.restoreMainWindow()
      let failure = ScreenshotError.fromCaptureError(error)
      NSLog("截图捕获失败：%@", failure.message)
      result(FlutterError(code: failure.code, message: failure.message, details: nil))
    }
  }

  // 快照全部显示器后展示覆盖层，等待一次拖拽选区或取消；每次完成回调恰好一次。
  @MainActor
  private func selectAndCrop() async throws -> (CaptureRegionPayload?, Bool) {
    let generation = captureGeneration
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    var snapshots: [CGDirectDisplayID: CGImage] = [:]
    for display in content.displays {
      snapshots[display.displayID] = try await coordinator.captureScreenImage(
        displayID: display.displayID
      )
    }
    // 快照为空时无需展示覆盖层，直接按取消完成。
    guard generation == captureGeneration, !snapshots.isEmpty else { return (nil, true) }
    // 汇总显示器、快照与缩放比例，在主线程一次性同步构建覆盖层，避免二次异步请求导致面板不出现。
    let pairs: [(display: SCDisplay, image: CGImage, scale: CGFloat)] = content.displays.compactMap { display in
      guard let image = snapshots[display.displayID] else { return nil }
      let scale = ScreenCaptureCoordinator.backingScaleFactor(for: display.displayID)
      return (display, image, scale)
    }
    guard !pairs.isEmpty else { return (nil, true) }
    return await withCheckedContinuation { continuation in
      // 先安装完成回调，再显示窗口，首次点击或 Esc 都必须能完成当前请求。
      completionPending = { payload, cancelled in
        continuation.resume(returning: (payload, cancelled))
      }
      presentOverlays(pairs: pairs)
    }
  }

  // 完成当前捕获会话；只允许生效一次，避免重复 resume 触发崩溃。
  private func finish(_ payload: CaptureRegionPayload?, cancelled: Bool) {
    guard let pending = completionPending else { return }
    completionPending = nil
    teardownOverlays()
    pending(payload, cancelled)
  }

  // 在主线程为每台显示器构建全屏选区面板；面板与视图由数组持有直到会话结束。
  private func presentOverlays(pairs: [(display: SCDisplay, image: CGImage, scale: CGFloat)]) {
    for pair in pairs {
      let display = pair.display
      let image = pair.image
      let scale = pair.scale
      // NSScreen 使用 Cocoa 坐标；跨屏不能把 ScreenCaptureKit 的屏幕坐标直接用于 NSPanel。
      let frame = NSScreen.screens.first(where: {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
      })?.frame ?? display.frame
      let localBounds = CGRect(origin: .zero, size: frame.size)
      let panel = SelectionOverlayPanel(
        contentRect: frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      panel.level = .screenSaver
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.ignoresMouseEvents = false
      let view = SelectionOverlayView(snapshot: image)
      view.frame = localBounds
      view.onComplete = { [weak self] selection in
        guard let self else { return }
        if let selection,
           let rect = ScreenCaptureCoordinator.cropPixelRect(
             from: selection,
             displayBounds: localBounds,
             backingScaleFactor: scale
           ) {
          do {
            let png = try self.coordinator.cropPNG(
              from: image,
              selection: selection,
              displayBounds: localBounds,
              backingScaleFactor: scale
            )
            let payload = CaptureRegionPayload(
              pngData: png,
              displayId: display.displayID,
              selection: selection.offsetBy(dx: frame.minX, dy: frame.minY),
              pixelWidth: rect.width,
              pixelHeight: rect.height
            )
            self.finish(payload, cancelled: false)
          } catch {
            self.finish(nil, cancelled: true)
          }
        } else {
          self.finish(nil, cancelled: true)
        }
      }
      panel.contentView = view
      overlayViews.append(view)
      overlayPanels.append(panel)
      panel.orderFrontRegardless()
      panel.makeKeyAndOrderFront(nil)
      panel.makeFirstResponder(view)
    }
    NSApp.activate(ignoringOtherApps: true)
    wireEscMonitor()
  }

  private func wireEscMonitor() {
    guard escMonitor == nil else { return }
    escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { // Esc
        self?.finish(nil, cancelled: true)
        return nil
      }
      return event
    }
  }

  private func teardownOverlays() {
    if let monitor = escMonitor {
      NSEvent.removeMonitor(monitor)
      escMonitor = nil
    }
    for view in overlayViews {
      view.onComplete = nil
    }
    overlayViews.removeAll()
    for panel in overlayPanels {
      panel.orderOut(nil)
    }
    overlayPanels.removeAll()
  }

  // 应用退出：注销全局快捷键、取消进行中的捕获并释放覆盖层。
  func shutdown() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    activeShortcut = ""
    cancelCapture()
    teardownOverlays()
  }

  // Dart 主动取消当前捕获会话（新会话替换或应用退出）。
  func cancelCapture() {
    captureGeneration += 1
    finish(nil, cancelled: true)
  }

  private func recognize(
    requestId: String,
    pngData: Data,
    result: @escaping FlutterResult
  ) async {
    do {
      let text = try await coordinator.recognizeText(in: pngData)
      result(text)
    } catch let error as ScreenshotError {
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      result(FlutterError(code: "ocrFailed", message: "OCR 识别失败", details: nil))
    }
  }
}

// 事件通道桥接：Dart 订阅后接收事件。
extension MacDesktopBridge: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
