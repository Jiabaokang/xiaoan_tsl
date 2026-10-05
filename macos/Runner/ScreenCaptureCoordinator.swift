import Cocoa
import ScreenCaptureKit
import Vision
import NaturalLanguage

// 屏幕快照与选区裁剪结果：PNG 数据与坐标系信息。
struct CaptureRegionPayload {
  let pngData: Data
  let displayId: CGDirectDisplayID
  let selection: CGRect        // 左下原点 point 坐标
  let pixelWidth: Int
  let pixelHeight: Int
}

// 截图、OCR 与语言识别协调器；每次捕获完成后释放全屏快照缓存。
final class ScreenCaptureCoordinator {

  // 选区坐标（左下原点 point）换算到截图像素（左上原点）的纯函数，便于单测。
  // displayBounds 使用左下原点 point 坐标；返回左上原点像素矩形；选区越界按屏幕裁切。
  static func cropPixelRect(
    from selection: CGRect,
    displayBounds: CGRect,
    backingScaleFactor: CGFloat
  ) -> (x: Int, y: Int, width: Int, height: Int)? {
    let scale = backingScaleFactor
    // 裁剪到显示器可见区域内。
    let clampedX = max(0, selection.minX)
    let clampedY = max(0, selection.minY)
    let clampedMaxX = min(displayBounds.maxX, selection.maxX)
    let clampedMaxY = min(displayBounds.maxY, selection.maxY)
    let width = clampedMaxX - clampedX
    let height = clampedMaxY - clampedY
    guard width > 1, height > 1 else { return nil }
    // 像素坐标：y 翻转（CGImage 原点在左上）。
    let pixelX = Int(round(clampedX * scale))
    let pixelY = Int(round((displayBounds.maxY - clampedMaxY) * scale))
    let pixelWidth = Int(round(width * scale))
    let pixelHeight = Int(round(height * scale))
    guard pixelWidth > 1, pixelHeight > 1 else { return nil }
    return (pixelX, pixelY, pixelWidth, pixelHeight)
  }

  // 取得指定显示器的全屏快照（完整屏幕，不含选区遮罩）。
  func captureScreenImage(displayID: CGDirectDisplayID) async throws -> CGImage {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    guard let display = content.displays.first(where: { $0.displayID == displayID })
    else {
      throw ScreenshotError.captureFailed("显示器 \(displayID) 不可用")
    }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    // SCDisplay 的尺寸单位为 point；快照像素必须与选区裁剪使用同一 Retina 倍率。
    let scale = Self.backingScaleFactor(for: displayID)
    config.width = Int(CGFloat(display.width) * scale)
    config.height = Int(CGFloat(display.height) * scale)
    config.showsCursor = false
    return try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: config
    )
  }

  // 通过 NSScreen 匹配显示器 ID，取得 backing scale factor；匹配失败按 1x 兜底。
  static func backingScaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
    for screen in NSScreen.screens {
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
      else { continue }
      if number.uint32Value == displayID {
        return screen.backingScaleFactor
      }
    }
    return 1.0
  }

  // 从全屏快照按选区裁剪出 PNG 数据。
  func cropPNG(
    from image: CGImage,
    selection: CGRect,
    displayBounds: CGRect,
    backingScaleFactor: CGFloat
  ) throws -> Data {
    guard let rect = Self.cropPixelRect(
      from: selection,
      displayBounds: displayBounds,
      backingScaleFactor: backingScaleFactor
    ) else {
      throw ScreenshotError.captureFailed("选区过小或超出屏幕")
    }
    guard let cropped = image.cropping(to: CGRect(
      x: rect.x, y: rect.y, width: rect.width, height: rect.height
    )) else {
      throw ScreenshotError.captureFailed("裁剪图片失败")
    }
    let rep = NSBitmapImageRep(cgImage: cropped)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      throw ScreenshotError.captureFailed("生成 PNG 失败")
    }
    return png
  }

  // Vision OCR：后台队列执行，输出按阅读顺序组织的文字块。
  func recognizeText(in pngData: Data) async throws -> String {
    guard let image = NSImage(data: pngData),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      throw ScreenshotError.ocrFailed("无法读取截图")
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [
      "en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR",
      "fr-FR", "de-DE", "es-ES", "pt-BR", "it-IT", "ru-RU",
    ]
    request.minimumTextHeight = 0.01
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw ScreenshotError.ocrFailed("OCR 执行失败")
    }
    // 按阅读顺序：从上到下（maxY 降序），同一行内从左到右（minX 升序）。
    let observations = (request.results ?? []).sorted { a, b in
      let ay = a.boundingBox.maxY
      let by = b.boundingBox.maxY
      if abs(ay - by) > 0.02 { return ay > by }
      return a.boundingBox.minX < b.boundingBox.minX
    }
    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
    return lines.joined(separator: "\n")
  }

  // Natural Language 返回标准语言代码或 nil。
  func identifyLanguage(of text: String) -> String? {
    guard !text.isEmpty else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage else { return nil }
    switch language {
    case .english: return "en"
    case .simplifiedChinese, .traditionalChinese: return "zh"
    case .japanese: return "ja"
    case .korean: return "ko"
    case .french: return "fr"
    case .german: return "de"
    case .spanish: return "es"
    case .portuguese: return "pt"
    case .italian: return "it"
    case .russian: return "ru"
    default: return nil
    }
  }
}

// 截图与快捷键统一错误。
enum ScreenshotError: Error {
  case permissionDenied(String)
  case captureFailed(String)
  case ocrFailed(String)
  case shortcutConflict(String)

  // 以实际捕获 API 的结果判断权限，避免预检状态阻断已授权的截图。
  static func fromCaptureError(_ error: Error) -> ScreenshotError {
    let native = error as NSError
    if native.domain == SCStreamError.errorDomain,
       native.code == SCStreamError.Code.userDeclined.rawValue {
      return .permissionDenied("屏幕访问被系统拒绝；已授权时请完全退出后独立启动应用，或检查启动 IDE 的录屏权限")
    }
    return .captureFailed("截图失败：\(native.domain) (\(native.code))，\(native.localizedDescription)")
  }

  var message: String {
    switch self {
    case .permissionDenied(let m): return m
    case .captureFailed(let m): return m
    case .ocrFailed(let m): return m
    case .shortcutConflict(let m): return m
    }
  }

  var code: String {
    switch self {
    case .permissionDenied: return "permissionDenied"
    case .captureFailed: return "captureFailed"
    case .ocrFailed: return "ocrFailed"
    case .shortcutConflict: return "shortcutConflict"
    }
  }
}
