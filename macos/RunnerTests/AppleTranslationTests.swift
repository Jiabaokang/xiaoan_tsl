import Cocoa
import FlutterMacOS
import XCTest
import Translation
#if canImport(Runner)
@testable import Runner
#endif

// 苹果桥的边界和生命周期测试；系统模型操作在会话边界替换，协调器与窗口保持真实。
final class AppleTranslationTests: XCTestCase {
  func testAppleArgumentsRejectInvalidPayload() {
    for payload: [String: Any] in [[:], ["requestId": ""], ["requestId": 1],
      ["requestId": "a", "text": ""], ["requestId": "a", "text": 1],
      ["requestId": "a", "text": String(repeating: "😀", count: 2500) + "a"]] {
      XCTAssertEqual(AppleTranslationBridge.validatePayload(method: "translateText", arguments: payload), "appleInvalidArguments")
    }
    XCTAssertNil(AppleTranslationBridge.validatePayload(method: "translateText", arguments: ["requestId": "a", "text": String(repeating: "😀", count: 2500)]))
    XCTAssertEqual(AppleTranslationBridge.validatePayload(method: "prepareAppleTranslation", arguments: ["requestId": "a", "sourceLanguage": "auto", "targetLanguage": "zh"]), "appleInvalidArguments")
  }

  func testAppleMapsSimplifiedChinese() {
    let languages = [Locale.Language(identifier: "zh-Hant"), Locale.Language(identifier: "en"), Locale.Language(identifier: "zh-Hans")]
    XCTAssertEqual(AppleTranslationBridge.mapLanguageCode("zh", supportedLanguages: languages)?.maximalIdentifier, Locale.Language(identifier: "zh-Hans").maximalIdentifier)
    XCTAssertNil(AppleTranslationBridge.mapLanguageCode("zh", supportedLanguages: [languages[0]]))
    XCTAssertNil(AppleTranslationBridge.mapLanguageCode("xx", supportedLanguages: languages))
    XCTAssertNil(AppleTranslationBridge.mapLanguageCode("auto", supportedLanguages: languages))
  }

  @MainActor
  func testAppleFinishesEachCallbackOnce() {
    let bridge = AppleTranslationBridge()
    var results: [Any?] = []
    bridge.handle(FlutterMethodCall(methodName: "prepareAppleTranslation", arguments: ["requestId": "a", "sourceLanguage": "en", "targetLanguage": "zh"])) { results.append($0) }
    bridge.cancel(requestId: "a")
    bridge.cancel(requestId: "a")
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual((results.first as? FlutterError)?.code, "appleCancelled")
  }

  @MainActor
  func testAppleRejectsUnpreparedTranslation() {
    let bridge = AppleTranslationBridge()
    var value: Any?
    bridge.handle(FlutterMethodCall(methodName: "translateText", arguments: ["requestId": "a", "text": "Hello"])) { value = $0 }
    XCTAssertEqual((value as? FlutterError)?.code, "appleInvalidRequest")
  }

  @MainActor
  func testAppleCancelIsIdempotent() {
    var called = 0
    AppleTranslationBridge().handle(FlutterMethodCall(methodName: "cancelAppleTranslation", arguments: ["requestId": "old"])) {
      called += 1
      XCTAssertNil($0)
    }
    XCTAssertEqual(called, 1)
  }

  // 替换系统会话 I/O，保留真实协调器、NSPanel、Task 和计时器。
  @MainActor
  private func makeBridge(
    timeouts: AppleTranslationBridge.Timeouts = .init(),
    prepare: @escaping () async throws -> Void = {},
    translate: @escaping (String) async throws -> String = { _ in "你好" }
  ) -> AppleTranslationBridge {
    _ = NSApplication.shared
    return AppleTranslationBridge(timeouts: timeouts, languagePair: { _, _ in
      (Locale.Language(identifier: "en"), Locale.Language(identifier: "zh-Hans"), "installed")
    }, makeHost: { bridge, request, _, _ in
      let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 120), styleMask: [.titled, .closable], backing: .buffered, defer: false)
      panel.isReleasedWhenClosed = false
      Task { await bridge.run(request, prepare: prepare, translate: translate) }
      return panel
    })
  }

  @MainActor
  private func prepare(_ bridge: AppleTranslationBridge, id: String = "a", result: @escaping FlutterResult) {
    bridge.handle(FlutterMethodCall(methodName: "prepareAppleTranslation", arguments: ["requestId": id, "sourceLanguage": "en", "targetLanguage": "zh"]), result: result)
  }

  @MainActor
  func testApplePreparationTimeoutFinishesOnceAndReleasesHost() async throws {
    let bridge = makeBridge(timeouts: .init(preparation: 0.04, preparedIdle: 1, translation: 1), prepare: { try await Task.sleep(nanoseconds: 1_000_000_000) })
    let done = expectation(description: "preparation timeout")
    var callbacks = 0
    prepare(bridge) { value in
      callbacks += 1
      XCTAssertEqual((value as? FlutterError)?.code, "applePreparationTimeout")
      done.fulfill()
    }
    let request = try XCTUnwrap(bridge.activeTask)
    await fulfillment(of: [done], timeout: 3)
    bridge.cancel(requestId: "a")
    try await Task.sleep(nanoseconds: 80_000_000)
    XCTAssertEqual(callbacks, 1)
    XCTAssertNil(bridge.activeTask)
    XCTAssertNil(request.hostPanel)
    XCTAssertNil(request.continuation)
    XCTAssertNil(request.prepareResult)
  }

  @MainActor
  func testApplePreparedIdleTimeoutClosesHost() async throws {
    let bridge = makeBridge(timeouts: .init(preparation: 1, preparedIdle: 0.04, translation: 1))
    let ready = expectation(description: "prepared")
    var callbacks = 0
    prepare(bridge) { value in callbacks += 1; XCTAssertNil(value); ready.fulfill() }
    let request = try XCTUnwrap(bridge.activeTask)
    await fulfillment(of: [ready], timeout: 3)
    XCTAssertEqual(request.phase, .prepared)
    XCTAssertTrue(request.hostPanel?.isVisible == true)
    try await Task.sleep(nanoseconds: 120_000_000)
    XCTAssertNil(bridge.activeTask)
    XCTAssertNil(request.hostPanel)
    XCTAssertNil(request.continuation)
    XCTAssertEqual(callbacks, 1)
  }

  @MainActor
  func testAppleTranslationTimeoutAndLateCompletionFinishOnce() async throws {
    let bridge = makeBridge(timeouts: .init(preparation: 1, preparedIdle: 1, translation: 0.03), translate: { _ in
      // 故意忽略取消模拟系统晚到结果，不能污染结束后的请求。
      try? await Task.sleep(nanoseconds: 100_000_000)
      return "late"
    })
    let ready = expectation(description: "prepared")
    prepare(bridge) { XCTAssertNil($0); ready.fulfill() }
    await fulfillment(of: [ready], timeout: 3)
    let request = try XCTUnwrap(bridge.activeTask)
    let done = expectation(description: "translation timed out")
    var callbacks = 0
    bridge.handle(FlutterMethodCall(methodName: "translateText", arguments: ["requestId": "a", "text": "hello"])) {
      callbacks += 1
      XCTAssertEqual(($0 as? FlutterError)?.code, "appleTimeout")
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 3)
    bridge.cancel(requestId: "a")
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(callbacks, 1)
    XCTAssertNil(request.hostPanel)
    XCTAssertNil(bridge.activeTask)
  }

  @MainActor
  func testOldAppleCancelDoesNotCloseNewHost() async throws {
    let bridge = makeBridge(timeouts: .init(preparation: 0.15, preparedIdle: 0.15, translation: 1))
    let firstReady = expectation(description: "first")
    prepare(bridge, id: "old") { XCTAssertNil($0); firstReady.fulfill() }
    await fulfillment(of: [firstReady], timeout: 3)
    bridge.cancel(requestId: "old")
    let ready = expectation(description: "new")
    prepare(bridge, id: "new") { XCTAssertNil($0); ready.fulfill() }
    await fulfillment(of: [ready], timeout: 3)
    let request = try XCTUnwrap(bridge.activeTask)
    let panel = try XCTUnwrap(request.hostPanel)
    bridge.cancel(requestId: "old")
    XCTAssertTrue(bridge.activeTask === request)
    XCTAssertTrue(panel.isVisible)
    let done = expectation(description: "success")
    bridge.handle(FlutterMethodCall(methodName: "translateText", arguments: ["requestId": "new", "text": "Hello"])) {
      let payload = $0 as? [String: String]
      XCTAssertEqual(payload?["requestId"], "new")
      XCTAssertEqual(payload?["translatedText"], "你好")
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 3)
    XCTAssertNil(bridge.activeTask)
    XCTAssertFalse(panel.isVisible)
  }

  @MainActor
  func testAppleBusyDuringLanguageLookupAndCancelBeforeLookupReturns() async throws {
    _ = NSApplication.shared
    var lookup: CheckedContinuation<AppleTranslationBridge.LanguagePair?, Never>?
    var hosts = 0
    let bridge = AppleTranslationBridge(languagePair: { _, _ in
      await withCheckedContinuation { lookup = $0 }
    }, makeHost: { _, _, _, _ in hosts += 1; return NSPanel() })
    let cancelled = expectation(description: "lookup cancelled")
    prepare(bridge, id: "old") { XCTAssertEqual(($0 as? FlutterError)?.code, "appleCancelled"); cancelled.fulfill() }
    await Task.yield()
    prepare(bridge, id: "other") { XCTAssertEqual(($0 as? FlutterError)?.code, "appleBusy") }
    bridge.cancel(requestId: "other")
    XCTAssertEqual(bridge.activeTask?.requestId, "old")
    bridge.cancel(requestId: "old")
    await fulfillment(of: [cancelled], timeout: 3)
    let pending = try XCTUnwrap(lookup)
    pending.resume(returning: (Locale.Language(identifier: "en"), Locale.Language(identifier: "zh-Hans"), "installed"))
    try await Task.sleep(nanoseconds: 30_000_000)
    XCTAssertEqual(hosts, 0)
    XCTAssertNil(bridge.activeTask)
  }

  @MainActor
  func testAppleHostCloseCancelsWaitingSession() async throws {
    let bridge = makeBridge()
    let ready = expectation(description: "prepared")
    prepare(bridge) { XCTAssertNil($0); ready.fulfill() }
    await fulfillment(of: [ready], timeout: 3)
    let request = try XCTUnwrap(bridge.activeTask)
    let host = try XCTUnwrap(request.hostPanel)
    XCTAssertTrue(bridge.owns(host))
    let child = NSPanel()
    host.addChildWindow(child, ordered: .above)
    XCTAssertTrue(bridge.owns(child))
    host.removeChildWindow(child)
    host.performClose(nil)
    XCTAssertNil(bridge.activeTask)
    XCTAssertNil(request.continuation)
    XCTAssertFalse(host.isVisible)
  }

  // 本机只读 API 验收：查询支持列表与语言对，不创建 session、不触发下载。
  @MainActor
  func testRealAppleLanguageAvailabilityReadOnly() async throws {
    guard #available(macOS 15.0, *) else { throw XCTSkip("macOS 15 required") }
    let availability = LanguageAvailability()
    let languages = await availability.supportedLanguages
    let source = try XCTUnwrap(AppleTranslationBridge.mapLanguageCode("en", supportedLanguages: languages))
    let target = try XCTUnwrap(AppleTranslationBridge.mapLanguageCode("zh", supportedLanguages: languages))
    let forward = await availability.status(from: source, to: target)
    let reverse = await availability.status(from: target, to: source)
    print("REAL_APPLE_SUPPORTED_LANGUAGES=\(languages.map(\.minimalIdentifier).sorted())")
    print("REAL_APPLE_PAIR en→zh-Hans=\(forward), zh-Hans→en=\(reverse)")
    XCTAssertNotEqual(forward, .unsupported)
    XCTAssertNotEqual(reverse, .unsupported)
    let bridge = AppleTranslationBridge()
    let mappedForward = await bridge.checkAvailability(sourceLanguage: "en", targetLanguage: "zh")
    let mappedReverse = await bridge.checkAvailability(sourceLanguage: "zh", targetLanguage: "en")
    XCTAssertEqual(mappedForward["status"], String(describing: forward))
    XCTAssertEqual(mappedReverse["status"], String(describing: reverse))
  }

  @MainActor
  func testOverlayPreparationSuspendsAndRestoresAutoDismiss() throws {
    _ = NSApplication.shared
    let view = OverlayResultView(frame: NSRect(x: 0, y: 0, width: 420, height: 190))
    func update(_ stage: OverlayStage) {
      view.update(with: .init(stage: stage, recognizedText: "Hello", translatedText: nil,
        canRetry: false, canConfigure: false, historySaveFailed: false))
    }
    func timer() -> Timer? {
      Mirror(reflecting: view).children.first { $0.label == "autoDismissTimer" }?.value as? Timer
    }
    update(.loading("OCR"))
    let previous = try XCTUnwrap(timer())
    XCTAssertEqual(previous.fireDate.timeIntervalSinceNow, 180, accuracy: 1)
    update(.preparingTranslation)
    XCTAssertFalse(previous.isValid)
    XCTAssertNil(timer())
    update(.loading("Translating"))
    XCTAssertTrue(timer()?.isValid == true)
    XCTAssertEqual(try XCTUnwrap(timer()).fireDate.timeIntervalSinceNow, 180, accuracy: 1)
  }

  @MainActor
  func testOverlayAllowsAppleHostAndSheetClicks() async throws {
    _ = NSApplication.shared
    let bridge = AppleTranslationBridge.shared
    let requestReady = expectation(description: "test host ready")
    // 独立协调器拥有测试宿主；面板使用注入的真实宿主归属判定。
    let owner = makeBridge()
    prepare(owner) { XCTAssertNil($0); requestReady.fulfill() }
    await fulfillment(of: [requestReady], timeout: 3)
    defer { owner.cancel(requestId: "a") }
    let host = try XCTUnwrap(owner.activeTask?.hostPanel)
    let panel = OverlayResultPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    panel.contentView = NSView(frame: .zero)
    // 不改全局单例状态，专用判定闭包只替换协调器实例。
    panel.isTranslationWindow = { owner.owns($0) }
    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
      modifierFlags: [], timestamp: 0, windowNumber: host.windowNumber, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1))
    XCTAssertFalse(panel.shouldDismiss(for: event))
    let other = NSPanel()
    let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
      modifierFlags: [], timestamp: 0, windowNumber: other.windowNumber, context: nil,
      eventNumber: 2, clickCount: 1, pressure: 1))
    XCTAssertTrue(panel.shouldDismiss(for: outside))
    XCTAssertFalse(bridge.owns(other))
  }

  @MainActor
  func testOverlayPreparingInvalidatesAlreadyStartedFade() async throws {
    _ = NSApplication.shared
    let view = OverlayResultView(frame: NSRect(x: 0, y: 0, width: 420, height: 190))
    var dismissed = 0
    view.onAction = { if case .dismiss = $0 { dismissed += 1 } }
    view.update(with: .init(stage: .loading("OCR"), recognizedText: nil, translatedText: nil,
      canRetry: false, canConfigure: false, historySaveFailed: false))
    let timer = try XCTUnwrap(Mirror(reflecting: view).children.first { $0.label == "autoDismissTimer" }?.value as? Timer)
    timer.fire()
    view.update(with: .init(stage: .preparingTranslation, recognizedText: nil, translatedText: nil,
      canRetry: false, canConfigure: false, historySaveFailed: false))
    try await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertEqual(dismissed, 0)
  }

  @MainActor
  func testScreenshotSnapshotRendersApplePreparation() throws {
    _ = NSApplication.shared
    let window = MainFlutterWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.showOverlayPanel(displayId: CGMainDisplayID(), selection: .zero)
    defer { window.shutdownOverlayPanel(); window.orderOut(nil) }
    window.updateOverlayResult(["stage": "preparingTranslation", "recognizedText": "Hello"])
    let view = try XCTUnwrap(window.overlayPanel?.contentView as? OverlayResultView)
    let snapshot = try XCTUnwrap(Mirror(reflecting: view).children.first { $0.label == "snapshot" }?.value as? OverlaySnapshot)
    guard case .preparingTranslation = snapshot.stage else { return XCTFail("preparingTranslation snapshot was not rendered") }
  }

  @MainActor
  func testScreenshotSnapshotUsesAppleErrorCode() throws {
    _ = NSApplication.shared
    let window = MainFlutterWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
    window.showOverlayPanel(displayId: CGMainDisplayID(), selection: .zero)
    defer { window.shutdownOverlayPanel(); window.orderOut(nil) }
    window.updateOverlayResult(["stage": "failed", "failure": "apple", "appleErrorCode": "appleBusy", "recognizedText": "Hello"])
    let view = try XCTUnwrap(window.overlayPanel?.contentView as? OverlayResultView)
    let snapshot = try XCTUnwrap(Mirror(reflecting: view).children.first { $0.label == "snapshot" }?.value as? OverlaySnapshot)
    guard case .failed(let message) = snapshot.stage else { return XCTFail("missing error") }
    XCTAssertEqual(message, AppleTranslationBridge.message("appleBusy"))
    XCTAssertFalse(snapshot.canConfigure)
  }

  // installed 才进入真实可见宿主，supported 直接跳过，绝不主动触发模型下载。
  @MainActor
  func testRealAppleInstalledSessionTranslatesAndReleasesVisibleHost() async throws {
    guard #available(macOS 15.0, *) else { throw XCTSkip("macOS 15 required") }
    _ = NSApplication.shared
    let bridge = AppleTranslationBridge()
    let availability = await bridge.checkAvailability(sourceLanguage: "en", targetLanguage: "zh")
    guard availability["status"] == "installed" else {
      throw XCTSkip("真实 en→zh-Hans 状态为 \(availability["status"] ?? "unknown")；需要人工确认下载后再验收真实会话")
    }
    let id = UUID().uuidString
    defer { bridge.cancel(requestId: id) }
    let ready = expectation(description: "real Apple session prepared")
    prepare(bridge, id: id) { XCTAssertNil($0); ready.fulfill() }
    let request = try XCTUnwrap(bridge.activeTask)
    await fulfillment(of: [ready], timeout: 35)
    let host = try XCTUnwrap(request.hostPanel)
    XCTAssertTrue(host.isVisible)
    XCTAssertNotNil(host.contentViewController)
    let done = expectation(description: "real translation")
    bridge.handle(FlutterMethodCall(methodName: "translateText", arguments: ["requestId": id, "text": "hello"])) {
      let payload = $0 as? [String: String]
      XCTAssertEqual(payload?["requestId"], id)
      XCTAssertFalse(payload?["translatedText"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
      XCTAssertNotEqual(payload?["translatedText"]?.lowercased(), "hello")
      print("REAL_APPLE_HELLO_RESULT=\(payload?["translatedText"] ?? "missing")")
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 35)
    XCTAssertNil(bridge.activeTask)
    XCTAssertNil(request.hostPanel)
    XCTAssertFalse(host.isVisible)
    XCTAssertNil(host.contentViewController)
  }
}
