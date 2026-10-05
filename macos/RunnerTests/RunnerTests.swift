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

  // 最小化的主窗口收到截图选区后必须恢复，用户才能看到识别进度和译文。
  @MainActor
  func testMinimizedWindowShowsScreenshotResult() async {
    let window = MainFlutterWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    let minimized = expectation(forNotification: NSWindow.didMiniaturizeNotification, object: window)
    window.miniaturize(nil)
    await fulfillment(of: [minimized], timeout: 5)
    XCTAssertTrue(window.isMiniaturized)
    let restored = expectation(forNotification: NSWindow.didDeminiaturizeNotification, object: window)
    window.showResultWindow(displayId: CGMainDisplayID(), selection: NSRect(x: 50, y: 50, width: 200, height: 100))
    await fulfillment(of: [restored], timeout: 5)
    XCTAssertFalse(window.isMiniaturized)
    XCTAssertTrue(window.isVisible)
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
