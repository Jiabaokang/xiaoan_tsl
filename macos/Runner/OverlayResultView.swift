import Cocoa

// 原位覆盖面板的显示阶段；与 Dart 侧 ScreenshotStage 对齐。
enum OverlayStage {
  case loading(String)     // OCR 或翻译进行中，附带提示文字
  case preparingTranslation // 等待苹果系统准备语言包
  case needsConfirm        // 语言不确定，等待用户确认
  case done                // 译文已就绪
  case failed(String)      // 出错，附带错误描述

  var isTerminal: Bool {
    switch self {
    case .done, .failed: return true
    default: return false
    }
  }
}

// 覆盖面板的完整快照；由 Dart 侧 updateResult 推送。
struct OverlaySnapshot {
  let stage: OverlayStage
  let recognizedText: String?
  let translatedText: String?
  let canRetry: Bool
  let canConfigure: Bool
  let historySaveFailed: Bool
}

// 底部工具条按钮的动作。
enum OverlayAction {
  case copy
  case reshoot
  case dismiss
  case confirm
  case retry
  case configure
}

// 原位译文覆盖视图：在截图选区位置显示翻译结果、加载状态或错误提示。
// 底部带迷你工具条，支持复制、按住查看原文（peek）、重截和关闭。
final class OverlayResultView: NSView {
  // 工具条动作回调。
  var onAction: ((OverlayAction) -> Void)?

  // 自动关闭计时器：3 分钟无操作后淡出。
  private var autoDismissTimer: Timer?
  private var dismissGeneration = 0
  private static let autoDismissInterval: TimeInterval = 180

  // 当前快照。
  private var snapshot: OverlaySnapshot?

  // Peek 模式：按住"原文"按钮时临时显示 OCR 原文。
  private var isPeeking = false

  // 子视图。
  private let contentLabel = NSTextField(wrappingLabelWithString: "")
  private let spinnerView = NSProgressIndicator()
  private let statusLabel = NSTextField(labelWithString: "")
  private let toolbarView = NSStackView()
  private let copyButton = NSButton()
  private let peekButton = NSButton()
  private let reshootButton = NSButton()
  private let closeButton = NSButton()
  private let confirmButton = NSButton()
  private let retryButton = NSButton()
  private let configureButton = NSButton()
  private let historyWarningLabel = NSTextField(labelWithString: "")

  // 面板引用，用于调整大小。
  weak var hostPanel: NSPanel?

  override init(frame: NSRect) {
    super.init(frame: frame)
    setupViews()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) 未实现")
  }

  private static func localized(_ chinese: String, _ english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
  }

  // MARK: - 视图搭建

  // 构建内容标签、加载指示器、状态文字和底部工具条。
  private func setupViews() {
    wantsLayer = true

    // 内容标签：显示译文或原文。
    contentLabel.isEditable = false
    contentLabel.isSelectable = true
    contentLabel.drawsBackground = false
    contentLabel.isBordered = false
    contentLabel.translatesAutoresizingMaskIntoConstraints = false
    contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    addSubview(contentLabel)

    // 加载指示器。
    spinnerView.style = .spinning
    spinnerView.controlSize = .small
    spinnerView.translatesAutoresizingMaskIntoConstraints = false
    spinnerView.isDisplayedWhenStopped = false
    addSubview(spinnerView)

    // 状态提示文字。
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.alignment = .center
    statusLabel.maximumNumberOfLines = 0
    statusLabel.lineBreakMode = .byWordWrapping
    addSubview(statusLabel)

    // 历史保存失败提示。
    historyWarningLabel.translatesAutoresizingMaskIntoConstraints = false
    historyWarningLabel.font = .systemFont(ofSize: 11)
    historyWarningLabel.textColor = .systemOrange
    historyWarningLabel.stringValue = Self.localized("历史记录保存失败", "History could not be saved")
    historyWarningLabel.isHidden = true
    addSubview(historyWarningLabel)

    // 工具条按钮。
    setupButton(copyButton, title: Self.localized("复制", "Copy"), image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: Self.localized("复制", "Copy")))
    setupButton(peekButton, title: Self.localized("原文", "Original"), image: NSImage(systemSymbolName: "eye", accessibilityDescription: Self.localized("原文", "Original")))
    setupButton(reshootButton, title: Self.localized("重截", "Reshoot"), image: NSImage(systemSymbolName: "crop", accessibilityDescription: Self.localized("重截", "Reshoot")))
    setupButton(closeButton, title: "", image: NSImage(systemSymbolName: "xmark", accessibilityDescription: Self.localized("关闭", "Close")))
    setupButton(confirmButton, title: Self.localized("按英文翻译", "Translate as English"), image: NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: Self.localized("确认", "Confirm")))
    setupButton(retryButton, title: Self.localized("重试", "Retry"), image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: Self.localized("重试", "Retry")))
    setupButton(configureButton, title: Self.localized("去设置", "Settings"), image: NSImage(systemSymbolName: "gear", accessibilityDescription: Self.localized("设置", "Settings")))

    copyButton.target = self
    copyButton.action = #selector(copyTapped)
    reshootButton.target = self
    reshootButton.action = #selector(reshootTapped)
    closeButton.target = self
    closeButton.action = #selector(closeTapped)
    confirmButton.target = self
    confirmButton.action = #selector(confirmTapped)
    retryButton.target = self
    retryButton.action = #selector(retryTapped)
    configureButton.target = self
    configureButton.action = #selector(configureTapped)

    // Peek 按钮使用按下/释放监听。
    peekButton.target = self
    peekButton.action = #selector(peekTapped)
    peekButton.isContinuous = false
    // 用 NSPressGestureRecognizer 实现按住查看。
    let pressGesture = NSPressGestureRecognizer(target: self, action: #selector(peekGesture(_:)))
    pressGesture.minimumPressDuration = 0.15
    peekButton.addGestureRecognizer(pressGesture)

    // 工具条布局。
    toolbarView.translatesAutoresizingMaskIntoConstraints = false
    toolbarView.orientation = .horizontal
    toolbarView.spacing = 8
    toolbarView.distribution = .fillEqually
    addSubview(toolbarView)

    // 约束。
    NSLayoutConstraint.activate([
      spinnerView.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinnerView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -16),

      statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      statusLabel.topAnchor.constraint(equalTo: spinnerView.bottomAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

      contentLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

      historyWarningLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      historyWarningLabel.bottomAnchor.constraint(equalTo: toolbarView.topAnchor, constant: -4),

      toolbarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      toolbarView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      toolbarView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      toolbarView.heightAnchor.constraint(equalToConstant: 28),
    ])
  }

  // 统一按钮样式：带图标和文字的圆角小按钮。
  private func setupButton(_ button: NSButton, title: String, image: NSImage?) {
    button.title = title
    button.image = image
    button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    button.bezelStyle = .recessed
    button.controlSize = .small
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setContentHuggingPriority(.defaultLow, for: .horizontal)
  }

  // MARK: - 状态更新

  // 接收新快照并刷新视图；面板大小可能随内容扩展。
  func update(with snapshot: OverlaySnapshot) {
    self.snapshot = snapshot
    isPeeking = false
    resetAutoDismiss()
    renderCurrentState()
  }

  // 根据当前快照阶段渲染视图元素。
  private func renderCurrentState() {
    guard let snapshot else { return }

    // 清空工具条。
    toolbarView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    historyWarningLabel.isHidden = true

    switch snapshot.stage {
    case .loading(let hint):
      contentLabel.isHidden = true
      spinnerView.isHidden = false
      spinnerView.startAnimation(nil)
      statusLabel.isHidden = false
      statusLabel.stringValue = hint

    case .preparingTranslation:
      contentLabel.isHidden = true
      spinnerView.isHidden = false
      spinnerView.startAnimation(nil)
      statusLabel.isHidden = false
      statusLabel.stringValue = Self.localized("正在准备苹果离线翻译，请完成系统提示",
        "Preparing Apple offline translation. Please complete the system prompt.")
      toolbarView.addArrangedSubview(reshootButton)
      toolbarView.addArrangedSubview(closeButton)

    case .needsConfirm:
      spinnerView.stopAnimation(nil)
      spinnerView.isHidden = true
      statusLabel.isHidden = true
      contentLabel.isHidden = false
      let text = snapshot.recognizedText ?? ""
      contentLabel.stringValue = text
      applyAdaptiveFont(for: text)
      toolbarView.addArrangedSubview(confirmButton)
      toolbarView.addArrangedSubview(closeButton)

    case .done:
      spinnerView.stopAnimation(nil)
      spinnerView.isHidden = true
      statusLabel.isHidden = true
      contentLabel.isHidden = false
      let text = isPeeking ? (snapshot.recognizedText ?? "") : (snapshot.translatedText ?? "")
      contentLabel.stringValue = text
      applyAdaptiveFont(for: text)
      historyWarningLabel.isHidden = !snapshot.historySaveFailed
      toolbarView.addArrangedSubview(copyButton)
      toolbarView.addArrangedSubview(peekButton)
      toolbarView.addArrangedSubview(reshootButton)
      toolbarView.addArrangedSubview(closeButton)

    case .failed(let message):
      spinnerView.stopAnimation(nil)
      spinnerView.isHidden = true
      statusLabel.isHidden = false
      statusLabel.stringValue = message
      contentLabel.isHidden = snapshot.recognizedText == nil
      if let recognized = snapshot.recognizedText {
        contentLabel.stringValue = recognized
        applyAdaptiveFont(for: recognized)
      }
      if snapshot.canConfigure {
        toolbarView.addArrangedSubview(configureButton)
      } else if snapshot.canRetry {
        toolbarView.addArrangedSubview(retryButton)
      }
      toolbarView.addArrangedSubview(reshootButton)
      toolbarView.addArrangedSubview(closeButton)
    }

    adjustPanelSizeIfNeeded()
  }

  // 根据选区高度和文字量自适应字号，最小 11pt。
  private func applyAdaptiveFont(for text: String) {
    let areaHeight = bounds.height - 44  // 减去工具条和边距
    let areaWidth = bounds.width - 16
    guard areaHeight > 0, areaWidth > 0, !text.isEmpty else {
      contentLabel.font = .systemFont(ofSize: 14)
      return
    }
    // 从 22pt 往下搜索合适字号。
    var fontSize: CGFloat = 22
    let minSize: CGFloat = 11
    while fontSize > minSize {
      let font = NSFont.systemFont(ofSize: fontSize)
      let maxSize = CGSize(width: areaWidth, height: .greatestFiniteMagnitude)
      let rect = (text as NSString).boundingRect(
        with: maxSize,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font]
      )
      if rect.height <= areaHeight {
        contentLabel.font = font
        return
      }
      fontSize -= 1
    }
    contentLabel.font = .systemFont(ofSize: minSize)
  }

  // 当文字在最小字号下仍放不下时，向下扩展面板（最多 2 倍选区高度）。
  private func adjustPanelSizeIfNeeded() {
    guard let panel = hostPanel, let snapshot, snapshot.stage.isTerminal else { return }
    let text: String
    switch snapshot.stage {
    case .done: text = isPeeking ? (snapshot.recognizedText ?? "") : (snapshot.translatedText ?? "")
    case .failed: text = snapshot.recognizedText ?? ""
    default: return
    }
    guard !text.isEmpty else { return }

    let font = contentLabel.font ?? .systemFont(ofSize: 11)
    let maxWidth = bounds.width - 16
    let textRect = (text as NSString).boundingRect(
      with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font]
    )
    let requiredHeight = textRect.height + 52  // 工具条 + 边距
    let currentHeight = panel.frame.height
    let maxHeight = currentHeight * 2  // 最多扩展到 2 倍
    if requiredHeight > currentHeight, requiredHeight <= maxHeight {
      var frame = panel.frame
      // 向下扩展（Cocoa 坐标：减小 y）。
      let delta = requiredHeight - currentHeight
      frame.origin.y -= delta
      frame.size.height = requiredHeight
      panel.setFrame(frame, display: true, animate: true)
    }
  }

  // MARK: - 外观

  override func updateLayer() {
    super.updateLayer()
    layer?.cornerRadius = 6
    if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
      layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.95).cgColor
      contentLabel.textColor = .white
    } else {
      layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.95).cgColor
      contentLabel.textColor = .black
    }
  }

  override var wantsUpdateLayer: Bool { true }

  // MARK: - 自动关闭

  // 重置 3 分钟自动关闭计时器。
  private func resetAutoDismiss() {
    dismissGeneration += 1
    autoDismissTimer?.invalidate()
    autoDismissTimer = nil
    hostPanel?.alphaValue = 1
    if case .preparingTranslation = snapshot?.stage { return }
    autoDismissTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDismissInterval, repeats: false) { [weak self] _ in
      self?.fadeOutAndDismiss()
    }
  }

  // 淡出动画后关闭面板。
  private func fadeOutAndDismiss() {
    let generation = dismissGeneration
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.3
      hostPanel?.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      guard let self, generation == self.dismissGeneration else { return }
      self.onAction?(.dismiss)
    })
  }

  // MARK: - 键盘事件

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {  // Esc
      onAction?(.dismiss)
    } else {
      super.keyDown(with: event)
    }
  }

  // MARK: - 按钮动作

  @objc private func copyTapped() {
    guard let text = snapshot?.translatedText, !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    // 短暂显示 ✓ 反馈。
    let originalTitle = copyButton.title
    copyButton.title = "✓"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.copyButton.title = originalTitle
    }
    resetAutoDismiss()
  }

  @objc private func peekTapped() {
    // 短按切换。
    isPeeking.toggle()
    renderCurrentState()
    resetAutoDismiss()
  }

  @objc private func peekGesture(_ gesture: NSPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      isPeeking = true
      renderCurrentState()
    case .ended, .cancelled:
      isPeeking = false
      renderCurrentState()
    default: break
    }
    resetAutoDismiss()
  }

  @objc private func reshootTapped() {
    onAction?(.reshoot)
  }

  @objc private func closeTapped() {
    onAction?(.dismiss)
  }

  @objc private func confirmTapped() {
    onAction?(.confirm)
  }

  @objc private func retryTapped() {
    onAction?(.retry)
  }

  @objc private func configureTapped() {
    onAction?(.configure)
  }

  // MARK: - 点击外部关闭

  // 面板级别的鼠标事件由 OverlayResultPanel 处理。

  deinit {
    autoDismissTimer?.invalidate()
  }
}

// 原位结果面板：无边框透明 NSPanel，定位在截图选区精确位置。
// 点击面板外区域或按 Esc 关闭。
final class OverlayResultPanel: NSPanel {
  // 系统翻译宿主的归属由协调器判定；子 sheet 与父窗口共用此路径。
  var isTranslationWindow: (NSWindow?) -> Bool = { AppleTranslationBridge.shared.owns($0) }

  // 点击面板外区域的全局监听。
  private var clickOutsideMonitor: Any?

  override var canBecomeKey: Bool { true }

  // 安装面板外点击监听；任何面板外的鼠标按下都会触发关闭。
  func installClickOutsideMonitor(action: @escaping () -> Void) {
    removeClickOutsideMonitor()
    clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self else { return event }
      if self.shouldDismiss(for: event) {
        action()
        return nil
      }
      return event
    }
  }

  func shouldDismiss(for event: NSEvent) -> Bool {
    guard let contentView, !isTranslationWindow(event.window) else { return false }
    let location = contentView.convert(event.locationInWindow, from: nil)
    return event.window !== self || !contentView.bounds.contains(location)
  }

  // 移除监听器。
  func removeClickOutsideMonitor() {
    if let monitor = clickOutsideMonitor {
      NSEvent.removeMonitor(monitor)
      clickOutsideMonitor = nil
    }
  }

  deinit {
    removeClickOutsideMonitor()
  }
}

