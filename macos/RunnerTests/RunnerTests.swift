import Cocoa
import Carbon.HIToolbox
import ScreenCaptureKit
import XCTest
import FlutterMacOS
import flutter_secure_storage_darwin
@testable import Runner

// 原生截图坐标换算的单元测试；不触达屏幕录制权限。
class RunnerTests: XCTestCase {

  // 后台启动的选区视图必须直接接受首次鼠标拖拽，不能把首次点击用于激活窗口。
  func testSelectionAcceptsFirstMouse() throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10,
      bitsPerComponent: 8, bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let view = SelectionOverlayView(snapshot: try XCTUnwrap(context.makeImage()))
    XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    XCTAssertTrue(view.acceptsFirstResponder)
    let panel = SelectionOverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    XCTAssertTrue(panel.canBecomeKey)
  }

  // 直接调用系统 Vision OCR，验证英文截图能被识别成翻译服务需要的文字。
  @MainActor
  func testVisionRecognizesEnglishText() async throws {
    let image = NSImage(size: NSSize(width: 600, height: 120))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 600, height: 120).fill()
    ("Hello world" as NSString).draw(at: NSPoint(x: 25, y: 40), withAttributes: [
      .font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black,
    ])
    image.unlockFocus()
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let text = try await ScreenCaptureCoordinator().recognizeText(in: png)
    XCTAssertTrue(text.lowercased().contains("hello world"), text)
  }

  // 截图结果应使用独立窗口，不能改变主窗口尺寸或最小化状态。
  @MainActor
  func testMinimizedWindowShowsScreenshotResult() async throws {
    let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first)
    let originalFrame = window.frame
    defer { window.restoreMainWindow() }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    let minimized = expectation(forNotification: NSWindow.didMiniaturizeNotification, object: window)
    window.miniaturize(nil)
    await fulfillment(of: [minimized], timeout: 5)
    XCTAssertTrue(window.isMiniaturized)
    window.showResultWindow(displayId: CGMainDisplayID(), selection: NSRect(x: 50, y: 50, width: 200, height: 100))
    XCTAssertTrue(window.isMiniaturized)
    XCTAssertEqual(window.frame, originalFrame)
    let result = try XCTUnwrap(NSApp.windows.first {
      $0 !== window && $0.contentViewController is FlutterViewController
    })
    defer { result.orderOut(nil) }
    XCTAssertTrue(result.isVisible)
    XCTAssertFalse((result.contentViewController as? FlutterViewController)?.engine ===
      (window.contentViewController as? FlutterViewController)?.engine)
  }

  // Dock 在译文可见时仍打开主页；两种关窗都不销毁主引擎，下一次截图复用结果窗。
  @MainActor
  func testDockAndResultCloseKeepMainWindowAvailable() throws {
    let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first)
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let originalFrame = window.frame
    window.showResultWindow(displayId: CGMainDisplayID(), selection: .zero)
    let result = try XCTUnwrap(window.resultWindow)
    defer { window.closeResultWindow() }
    window.orderOut(nil)
    XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true))
    XCTAssertTrue(window.isVisible)
    XCTAssertTrue(result.isVisible)
    XCTAssertEqual(window.frame, originalFrame)

    // 框选隐藏两个窗口；关闭结果只隐藏结果窗并恢复主页。
    window.hideWindowsForCapture()
    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(result.isVisible)
    window.showResultWindow(displayId: CGMainDisplayID(), selection: .zero)
    result.performClose(nil)
    XCTAssertFalse(result.isVisible)
    XCTAssertTrue(window.isVisible)
    XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    window.showResultWindow(displayId: CGMainDisplayID(), selection: .zero)
    XCTAssertTrue(window.resultWindow === result)
    XCTAssertTrue(result.isVisible)
    window.performClose(nil)
    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(result.isVisible)
    XCTAssertNotNil(window.contentViewController)
  }

  // 只把 ScreenCaptureKit 的实际拒绝识别为权限错误，保留其他捕获错误的诊断信息。
  func testScreenCaptureErrorClassification() {
    let denied = NSError(domain: SCStreamError.errorDomain,
                         code: SCStreamError.Code.userDeclined.rawValue)
    XCTAssertEqual(ScreenshotError.fromCaptureError(denied).code, "permissionDenied")
    for error in [
      NSError(domain: SCStreamError.errorDomain,
              code: SCStreamError.Code.internalError.rawValue),
      NSError(domain: "OtherCaptureError", code: denied.code),
    ] {
      let mapped = ScreenshotError.fromCaptureError(error)
      XCTAssertEqual(mapped.code, "captureFailed")
      XCTAssertTrue(mapped.message.contains(error.domain))
      XCTAssertTrue(mapped.message.contains(String(error.code)))
    }
  }

  // 使用独立服务名验证真实钥匙串；覆盖重复保存和重复删除，不触碰用户凭据。
  func testLocalKeychainCredentialLifecycle() async throws {
    let plugin = FlutterSecureStorageDarwinPlugin()
    let options = [
      "accountName": "xiaoan_tsl.keychain_test.\(UUID().uuidString)",
      "usesDataProtectionKeychain": "false",
      "accessibility": "first_unlock",
      "synchronizable": "false",
    ]
    // 通过插件公开通道执行，确保测试覆盖实际链接的 Apple 插件版本。
    func call(_ method: String, value: String? = nil) async throws -> Any? {
      var arguments: [String: Any] = ["key": "probe", "options": options]
      if let value { arguments["value"] = value }
      let output = await withCheckedContinuation { continuation in
        plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) {
          continuation.resume(returning: $0)
        }
      }
      if let error = output as? FlutterError {
        throw NSError(domain: "KeychainRegression", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: error.message ?? error.code])
      }
      return output
    }
    do {
      _ = try await call("delete")
      _ = try await call("write", value: "first")
      let first = try await call("read") as? String
      XCTAssertEqual(first, "first")
      _ = try await call("write", value: "updated")
      let updated = try await call("read") as? String
      XCTAssertEqual(updated, "updated")
      _ = try await call("delete")
      _ = try await call("delete")
      let deleted = try await call("read")
      XCTAssertNil(deleted)
    } catch {
      _ = try? await call("delete")
      throw error
    }
  }

  // Retina 缩放：点坐标乘以 scaleFactor，Y 翻转（CGImage 左上原点）。
  func testRetinaScaleAndYFlip() {
    let displayBounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
    // 左下原点选区：(100, 100, 100, 50)，即屏幕上部区域。
    let selection = CGRect(x: 100, y: 100, width: 100, height: 50)
    let rect = ScreenCaptureCoordinator.cropPixelRect(
      from: selection,
      displayBounds: displayBounds,
      backingScaleFactor: 2.0
    )
    XCTAssertNotNil(rect)
    // 左上原点像素：x=200；y=(800-150)*2=1300；宽 200；高 100。
    XCTAssertEqual(rect?.x, 200)
    XCTAssertEqual(rect?.y, 1300)
    XCTAssertEqual(rect?.width, 200)
    XCTAssertEqual(rect?.height, 100)
  }

  // 非 Retina 屏：1x 直接换算。
  func testNonRetinaScale() {
    let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let selection = CGRect(x: 10, y: 20, width: 300, height: 120)
    let rect = ScreenCaptureCoordinator.cropPixelRect(
      from: selection,
      displayBounds: displayBounds,
      backingScaleFactor: 1.0
    )
    XCTAssertEqual(rect?.x, 10)
    XCTAssertEqual(rect?.y, 940) // 1080 - (20 + 120)
    XCTAssertEqual(rect?.width, 300)
    XCTAssertEqual(rect?.height, 120)
  }

  // 负坐标：起点越界按屏幕边界裁切到 0。
  func testNegativeOriginClamped() {
    let displayBounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
    let selection = CGRect(x: -120, y: 40, width: 640, height: 200)
    let rect = ScreenCaptureCoordinator.cropPixelRect(
      from: selection,
      displayBounds: displayBounds,
      backingScaleFactor: 2.0
    )
    XCTAssertEqual(rect?.x, 0)
    XCTAssertEqual(rect?.width, 520 * 2)
    XCTAssertEqual(rect?.y, (800 - 240) * 2)
    XCTAssertEqual(rect?.height, 200 * 2)
  }

  // 超出屏幕边缘：按显示器边界裁切。
  func testBeyondScreenEdgeClamped() {
    let displayBounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
    let selection = CGRect(x: 1000, y: 700, width: 600, height: 400)
    let rect = ScreenCaptureCoordinator.cropPixelRect(
      from: selection,
      displayBounds: displayBounds,
      backingScaleFactor: 2.0
    )
    XCTAssertEqual(rect?.width, (1280 - 1000) * 2)
    XCTAssertEqual(rect?.height, (800 - 700) * 2)
  }

  // 极小或空选区视为取消，返回 nil。
  func testTinySelectionReturnsNil() {
    let displayBounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
    let selection = CGRect(x: 100, y: 100, width: 1, height: 1)
    XCTAssertNil(ScreenCaptureCoordinator.cropPixelRect(
      from: selection,
      displayBounds: displayBounds,
      backingScaleFactor: 2.0
    ))
  }

  // 完全在屏幕外的选区返回 nil。
  func testFullyOutsideReturnsNil() {
    let displayBounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
    let selection = CGRect(x: 2000, y: 2000, width: 100, height: 100)
    XCTAssertNil(ScreenCaptureCoordinator.cropPixelRect(
      from: selection,
      displayBounds: displayBounds,
      backingScaleFactor: 1.0
    ))
  }

  // 默认组合 Control + Option + T 的解析。
  func testParseDefaultShortcut() {
    let parsed = MacDesktopBridge.parseShortcut("Control+Option+T")
    let modifiers = parsed?.modifiers ?? 0
    XCTAssertEqual(parsed?.keyCode, UInt32(kVK_ANSI_T))
    XCTAssertEqual(modifiers & UInt32(controlKey), UInt32(controlKey))
    XCTAssertEqual(modifiers & UInt32(optionKey), UInt32(optionKey))
  }

  // Command + Shift + 9 的数字键解析。
  func testParseCommandShiftDigit() {
    let parsed = MacDesktopBridge.parseShortcut("Command+Shift+9")
    let modifiers = parsed?.modifiers ?? 0
    XCTAssertEqual(parsed?.keyCode, UInt32(kVK_ANSI_9))
    XCTAssertEqual(modifiers & UInt32(cmdKey), UInt32(cmdKey))
    XCTAssertEqual(modifiers & UInt32(shiftKey), UInt32(shiftKey))
  }

  // 缺少按键或未知修饰键返回 nil。
  func testParseInvalidShortcut() {
    XCTAssertNil(MacDesktopBridge.parseShortcut("Control+Option"))
    XCTAssertNil(MacDesktopBridge.parseShortcut("Foo+Bar"))
    XCTAssertNil(MacDesktopBridge.parseShortcut("Control+Option+Delete"))
  }
}

// 使用真实文件锁验证跨路径启动交接，不加载 Flutter 或启动应用。
final class MacAppLaunchTests: XCTestCase {
  // 每项测试使用独立锁目录，避免触碰真实应用的锁。
  func lockURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("instance.lock")
  }

  // 已运行的 Debug 必须被激活，新的 Release 不能夺取其锁。
  func testReleaseActivatesDebug() throws {
    let url = try lockURL()
    let existing = try MacAppLaunchLease.acquire(at: url, isDebug: true, peerAction: { _, _ in false })
    var actions: [MacAppLaunchLease.Action] = []
    let duplicate = try MacAppLaunchLease.acquire(at: url, isDebug: false, timeout: 0.1) { owner, action in
      XCTAssertTrue(owner.isDebug)
      actions.append(action)
      return true
    }
    XCTAssertNil(duplicate)
    XCTAssertEqual(actions, [.activate])
    withExtendedLifetime(existing) {}
  }

  // Debug 请求 Release 退出后，必须等旧锁真正释放才允许继续。
  func testDebugWaitsForReleaseLock() throws {
    let url = try lockURL()
    var existing = try MacAppLaunchLease.acquire(at: url, isDebug: false, peerAction: { _, _ in false })
    XCTAssertNotNil(existing)
    var actions: [MacAppLaunchLease.Action] = []
    let debug = try MacAppLaunchLease.acquire(at: url, isDebug: true, timeout: 0.2) { owner, action in
      XCTAssertFalse(owner.isDebug)
      actions.append(action)
      existing = nil
      return true
    }
    XCTAssertNotNil(debug)
    XCTAssertEqual(actions, [.yieldToDebug])
  }

  // 旧 Release 拒绝退出时，Debug 必须超时报错，不能并行创建引擎。
  func testRefusedTakeoverTimesOut() throws {
    let url = try lockURL()
    let existing = try MacAppLaunchLease.acquire(at: url, isDebug: false, peerAction: { _, _ in false })
    XCTAssertThrowsError(try MacAppLaunchLease.acquire(at: url, isDebug: true, timeout: 0.02) { _, action in
      XCTAssertEqual(action, .yieldToDebug)
      return true
    })
    withExtendedLifetime(existing) {}
  }

  // 同类重复启动一律激活原实例；不因不同构建路径重复启动。
  func testSameModeActivatesExisting() throws {
    for isDebug in [false, true] {
      let url = try lockURL()
      let existing = try MacAppLaunchLease.acquire(at: url, isDebug: isDebug, peerAction: { _, _ in false })
      let duplicate = try MacAppLaunchLease.acquire(at: url, isDebug: isDebug, timeout: 0.1) { _, action in
        XCTAssertEqual(action, .activate)
        return true
      }
      XCTAssertNil(duplicate)
      withExtendedLifetime(existing) {}
    }
  }

  // 异常退出遗留的元数据不代表运行实例；释放内核锁后下一次应能启动。
  func testStaleMetadataDoesNotBlockStartup() throws {
    let url = try lockURL()
    var existing = try MacAppLaunchLease.acquire(at: url, isDebug: false, peerAction: { _, _ in false })
    XCTAssertNotNil(existing)
    existing = nil
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    let next = try MacAppLaunchLease.acquire(at: url, isDebug: true) { _, _ in
      XCTFail("未持锁的旧元数据不能触发激活或退出")
      return true
    }
    XCTAssertNotNil(next)
  }

  // 持锁实例尚未就绪或身份校验不通过时，不能绕过锁启动第二个引擎。
  func testUnavailablePeerDoesNotBypassLock() throws {
    let url = try lockURL()
    let existing = try MacAppLaunchLease.acquire(at: url, isDebug: true, peerAction: { _, _ in false })
    XCTAssertThrowsError(try MacAppLaunchLease.acquire(at: url, isDebug: false, timeout: 0.02) { _, _ in false })
    withExtendedLifetime(existing) {}
  }

  // 持锁期间元数据不完整时等待重试，不能猜测对端模式或释放它的锁。
  func testIncompleteMetadataDoesNotTriggerPeerAction() throws {
    let url = try lockURL()
    let existing = try MacAppLaunchLease.acquire(at: url, isDebug: false, peerAction: { _, _ in false })
    try Data("{".utf8).write(to: url)
    XCTAssertThrowsError(try MacAppLaunchLease.acquire(at: url, isDebug: true, timeout: 0.02) { _, _ in
      XCTFail("不完整的身份记录不能触发跨进程动作")
      return true
    })
    withExtendedLifetime(existing) {}
  }
}
