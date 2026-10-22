import Cocoa
import FlutterMacOS
import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

// 苹果离线翻译原生桥接器与请求协调器：在 macOS 15+ 管理会话宿主、系统语言包准备、端侧翻译与取消。
@MainActor
final class AppleTranslationBridge: NSObject, NSWindowDelegate {
  static let shared = AppleTranslationBridge()

  // 每个请求独占回调、等待点、计时器和宿主；对象身份隔离同 ID 的迟到回调。
  final class ActiveTask {
    enum Phase { case preparing, prepared, translating, finished }
    let requestId: String
    var phase = Phase.preparing
    var hostPanel: NSPanel?
    var prepareResult: FlutterResult?
    var translateResult: FlutterResult?
    var continuation: CheckedContinuation<String, Error>?
    var timer: DispatchWorkItem?
    var operation: Task<Void, Never>?
    var lookup: Task<Void, Never>?

    init(requestId: String, result: @escaping FlutterResult) {
      self.requestId = requestId
      prepareResult = result
    }
  }

  // 正式超时与可注入的较短测试时限共用同一计时路径。
  struct Timeouts {
    var preparation: TimeInterval = 600
    var preparedIdle: TimeInterval = 30
    var translation: TimeInterval = 30
  }

  typealias LanguagePair = (source: Locale.Language, target: Locale.Language, status: String)
  typealias HostFactory = (AppleTranslationBridge, ActiveTask, Locale.Language, Locale.Language) -> NSPanel
  private(set) var activeTask: ActiveTask?
  private let timeouts: Timeouts
  private let languagePair: (String, String) async -> LanguagePair?
  private let makeHost: HostFactory

  init(timeouts: Timeouts = Timeouts(),
       languagePair: ((String, String) async -> LanguagePair?)? = nil,
       makeHost: HostFactory? = nil) {
    self.timeouts = timeouts
    self.languagePair = languagePair ?? { await Self.resolveLanguagePair($0, $1) }
    self.makeHost = makeHost ?? { bridge, request, source, target in
      // 所有 15+ 类型只能在可用性检查之后创建。
      if #available(macOS 15.0, *) {
        return bridge.createHost(request, source: source, target: target)
      }
      preconditionFailure("Apple translation requires macOS 15")
    }
    super.init()
  }

  func checkAvailability(sourceLanguage: String, targetLanguage: String) async -> [String: String] {
    guard #available(macOS 15.0, *) else { return ["status": "platformUnsupported"] }
    let pair = await languagePair(sourceLanguage, targetLanguage)
    return ["status": pair?.status ?? "unsupported"]
  }

  private static func resolveLanguagePair(_ source: String, _ target: String) async -> LanguagePair? {
    guard #available(macOS 15.0, *) else { return nil }
    let availability = LanguageAvailability()
    let languages = await availability.supportedLanguages
    guard let from = mapLanguageCode(source, supportedLanguages: languages),
      let to = mapLanguageCode(target, supportedLanguages: languages) else { return nil }
    let status = await availability.status(from: from, to: to)
    switch status {
    case .installed: return (from, to, "installed")
    case .supported: return (from, to, "supported")
    case .unsupported: return nil
    @unknown default: return nil
    }
  }

  // 映射应用语言代码至系统 Locale.Language；简中必须映射至 zh-Hans，严禁误选繁中。
  nonisolated static func mapLanguageCode(
    _ code: String,
    supportedLanguages: [Locale.Language] = []
  ) -> Locale.Language? {
    guard code != "auto", !code.isEmpty else { return nil }
    let requested = Locale.Language(identifier: code == "zh" ? "zh-Hans" : code)
    return supportedLanguages.first { language in
      guard language.languageCode == requested.languageCode else { return false }
      return language.script == requested.script
    }
  }

  // 校验参数有效性，对空 ID、超长文本、类型错误等返回错误代码。
  nonisolated static func validatePayload(
    method: String,
    arguments: [String: Any]?
  ) -> String? {
    guard let arguments else { return "appleInvalidArguments" }
    if method != "appleTranslationAvailability" {
      guard let id = arguments["requestId"] as? String,
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return "appleInvalidArguments" }
    }
    if method == "prepareAppleTranslation" || method == "appleTranslationAvailability" {
      for key in ["sourceLanguage", "targetLanguage"] {
        guard let code = arguments[key] as? String,
          code.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil,
          code != "auto"
        else { return "appleInvalidArguments" }
      }
    }
    if method == "translateText" {
      guard let text = arguments["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        utf16Length(text) <= 5000
      else { return "appleInvalidArguments" }
    }
    return nil
  }

  // 计算与 Dart 侧 String.length 一致的 UTF-16 代码单元长度。
  nonisolated static func utf16Length(_ text: String) -> Int {
    return text.utf16.count
  }

  // 方法通道在主线程串行修改请求状态；坏参数不得被默认值吞掉。
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let methods = ["appleTranslationAvailability", "prepareAppleTranslation", "translateText", "cancelAppleTranslation"]
    guard methods.contains(call.method) else { result(FlutterMethodNotImplemented); return }
    let arguments = call.arguments as? [String: Any]
    if let code = Self.validatePayload(method: call.method, arguments: arguments) {
      result(Self.failure(code)); return
    }
    guard let arguments else { return }
    guard #available(macOS 15.0, *) else {
      result(call.method == "appleTranslationAvailability" ? ["status": "platformUnsupported"] : Self.failure("appleUnsupported"))
      return
    }
    if call.method == "appleTranslationAvailability" {
      let source = arguments["sourceLanguage"] as! String
      let target = arguments["targetLanguage"] as! String
      Task { result(await checkAvailability(sourceLanguage: source, targetLanguage: target)) }
      return
    }
    let id = arguments["requestId"] as! String
    switch call.method {
    case "prepareAppleTranslation":
      guard activeTask == nil else { result(Self.failure("appleBusy")); return }
      let request = ActiveTask(requestId: id, result: result)
      activeTask = request
      armTimer(request, seconds: timeouts.preparation, code: "applePreparationTimeout")
      let source = arguments["sourceLanguage"] as! String
      let target = arguments["targetLanguage"] as! String
      request.lookup = Task { [weak self, weak request] in
        guard let self, let request else { return }
        let pair = await languagePair(source, target)
        guard activeTask === request, !Task.isCancelled else { return }
        guard let pair, pair.status != "unsupported" else {
          finish(request, error: "appleUnsupportedLanguage"); return
        }
        let panel = makeHost(self, request, pair.source, pair.target)
        request.hostPanel = panel
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    case "translateText":
      guard let request = activeTask, request.requestId == id,
        request.phase == .prepared, let continuation = request.continuation
      else { result(Self.failure("appleInvalidRequest")); return }
      request.phase = .translating
      request.translateResult = result
      request.continuation = nil
      armTimer(request, seconds: timeouts.translation, code: "appleTimeout")
      continuation.resume(returning: arguments["text"] as! String)
    case "cancelAppleTranslation":
      cancel(requestId: id)
      result(nil)
    default: break
    }
  }

  // SwiftUI 的同一 translationTask 始终等待本方法，绝不在闭包结束后复用 session。
  func run(_ request: ActiveTask,
           prepare: @escaping () async throws -> Void,
           translate: @escaping (String) async throws -> String) async {
    guard activeTask === request, request.operation == nil else { return }
    let operation = Task { @MainActor [weak self, weak request] in
      guard let self, let request else { return }
      do {
        try Task.checkCancellation()
        guard activeTask === request else { return }
        try await prepare()
        try Task.checkCancellation()
        guard activeTask === request else { return }
        let text: String = try await withCheckedThrowingContinuation { continuation in
          request.continuation = continuation
          request.phase = .prepared
          self.armTimer(request, seconds: self.timeouts.preparedIdle, code: "appleTimeout")
          let callback = request.prepareResult
          request.prepareResult = nil
          callback?(nil)
        }
        try Task.checkCancellation()
        let translated = try await translate(text)
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          finish(request, error: "appleTranslationFailed"); return
        }
        finish(request, translatedText: translated)
      } catch {
        finish(request, error: Self.errorCode(error, preparing: request.phase == .preparing))
      }
    }
    request.operation = operation
    await withTaskCancellationHandler {
      await operation.value
    } onCancel: {
      Task { @MainActor [weak self, weak request] in
        guard let self, let request else { return }
        self.finish(request, error: "appleCancelled")
      }
    }
  }

  // 三种计时器均捕获请求对象，旧计时器不能终结新宿主。
  private func armTimer(_ request: ActiveTask, seconds: TimeInterval, code: String) {
    request.timer?.cancel()
    let timer = DispatchWorkItem { [weak self, weak request] in
      guard let self, let request else { return }
      self.finish(request, error: code)
    }
    request.timer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timer)
  }

  // 先使请求失效、摘除所有等待点，再关闭宿主和通知调用方，保证竞争时恰好完成一次。
  private func finish(_ request: ActiveTask, translatedText: String? = nil, error: String? = nil) {
    guard activeTask === request, request.phase != .finished else { return }
    request.phase = .finished
    activeTask = nil
    request.timer?.cancel()
    request.timer = nil
    request.lookup?.cancel()
    request.lookup = nil
    request.operation?.cancel()
    request.operation = nil
    let continuation = request.continuation
    request.continuation = nil
    let prepareResult = request.prepareResult
    let translateResult = request.translateResult
    request.prepareResult = nil
    request.translateResult = nil
    request.hostPanel?.delegate = nil
    request.hostPanel?.orderOut(nil)
    request.hostPanel?.contentViewController = nil
    request.hostPanel?.close()
    request.hostPanel = nil
    let failure = Self.failure(error ?? "appleCancelled")
    continuation?.resume(throwing: CancellationError())
    prepareResult?(failure)
    if let translatedText, error == nil {
      translateResult?(["requestId": request.requestId, "translatedText": translatedText])
    } else {
      translateResult?(failure)
    }
  }

  func cancel(requestId: String) {
    guard let request = activeTask, request.requestId == requestId else { return }
    finish(request, error: "appleCancelled")
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if let request = activeTask, request.hostPanel === sender {
      finish(request, error: "appleCancelled")
    }
    return false
  }

  // 准备宿主及其系统 sheet 的点击应完整传递，不能触发截图面板的外部关闭。
  func owns(_ window: NSWindow?) -> Bool {
    guard let host = activeTask?.hostPanel else { return false }
    var candidate = window
    while let current = candidate {
      if current === host { return true }
      candidate = current.sheetParent ?? current.parent
    }
    return false
  }

  @available(macOS 15.0, *)
  private func createHost(_ request: ActiveTask, source: Locale.Language, target: Locale.Language) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 190),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    panel.title = "苹果离线翻译 / Apple Offline Translation"
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .modalPanel
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentViewController = NSHostingController(rootView: AppleTranslationHostView(
      configuration: .init(source: source, target: target),
      cancel: { [weak self, weak request] in
        guard let self, let request, self.activeTask === request else { return }
        self.finish(request, error: "appleCancelled")
      },
      action: { [weak self, weak request] session in
        guard let self, let request else { return }
        await self.run(request, prepare: { try await session.prepareTranslation() },
                       translate: { try await session.translate($0).targetText })
      }))
    panel.center()
    return panel
  }

  // 仅匹配 SDK 公共错误和标准取消，不解析系统本地化描述。
  nonisolated static func errorCode(_ error: Error, preparing: Bool) -> String {
    if error is CancellationError { return "appleCancelled" }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
      return "appleCancelled"
    }
    if #available(macOS 26.0, *), TranslationError.alreadyCancelled ~= error {
      return "appleCancelled"
    }
    if #available(macOS 15.0, *) {
      switch error {
      case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage,
           TranslationError.unsupportedLanguagePairing:
        return "appleUnsupportedLanguage"
      default: break
      }
    }
    return preparing ? "applePreparationFailed" : "appleTranslationFailed"
  }

  nonisolated static func failure(_ code: String) -> FlutterError {
    FlutterError(code: code, message: message(code), details: nil)
  }

  nonisolated static func message(_ code: String, chinese: Bool = Locale.preferredLanguages.first?.hasPrefix("zh") ?? true) -> String {
    switch code {
    case "appleUnsupported": return chinese ? "当前系统不支持苹果离线翻译" : "Apple offline translation is unavailable on this system."
    case "appleUnsupportedLanguage": return chinese ? "所选语言组合暂不支持苹果离线翻译" : "This language pair is not supported by Apple offline translation."
    case "appleCancelled": return chinese ? "已取消苹果离线翻译" : "Apple offline translation cancelled."
    case "applePreparationFailed": return chinese ? "语言包准备失败，请检查网络和可用空间后重试" : "Language preparation failed. Check your connection and available storage, then retry."
    case "applePreparationTimeout": return chinese ? "语言包准备超时，请稍后重试" : "Language preparation timed out. Please try again later."
    case "appleBusy": return chinese ? "苹果翻译正在处理另一项任务，请稍后重试" : "Apple translation is handling another request. Please try again later."
    case "appleTimeout": return chinese ? "翻译超时，请重试" : "Translation timed out. Please retry."
    default: return chinese ? "苹果离线翻译失败，请重试" : "Apple offline translation failed. Please retry."
    }
  }
}

// 真正可见的 SwiftUI 会话宿主；系统下载 sheet 附着此视图生命周期。
@available(macOS 15.0, *)
private struct AppleTranslationHostView: View {
  let configuration: TranslationSession.Configuration
  let cancel: () -> Void
  let action: (TranslationSession) async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(Locale.preferredLanguages.first?.hasPrefix("zh") == true
        ? "正在准备苹果离线翻译，请完成系统提示"
        : "Preparing Apple offline translation. Please complete the system prompt.")
      Text(Locale.preferredLanguages.first?.hasPrefix("zh") == true
        ? "首次准备可能需要联网下载，语言包由系统管理。"
        : "First use may require a download. Language packs are managed by macOS.")
        .font(.caption).foregroundStyle(.secondary)
      Button(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "取消" : "Cancel", action: cancel)
        .keyboardShortcut(.cancelAction)
    }
    .padding(24)
    .frame(minWidth: 380, minHeight: 140)
    .translationTask(configuration, action: action)
  }
}
