import Darwin
import Flutter
import MLKitCommon
import MLKitTranslate
import XCTest
@testable import Runner

/// 验证下载桥接对 SDK 条件、真实进度、通知和错误的对外契约。
class RunnerTests: XCTestCase {

  /// 防止 Wi-Fi 策略被错误地硬编码成允许蜂窝网络。
  func testDownloadConditionsRespectWifiOnly() {
    XCTAssertFalse(ModelDownloadBridge.downloadConditions(wifiOnly: true).allowsCellularAccess)
    XCTAssertTrue(ModelDownloadBridge.downloadConditions(wifiOnly: false).allowsCellularAccess)
    XCTAssertTrue(ModelDownloadBridge.downloadConditions(wifiOnly: true).allowsBackgroundDownloading)
  }

  /// 未知总量不能变成虚构百分比，真实分数应原样传出。
  func testProgressRequiresKnownTotalAndUsesActualFraction() {
    let progress = Progress(totalUnitCount: 0)
    XCTAssertNil(ModelDownloadBridge.progressFraction(progress))
    progress.totalUnitCount = -1
    XCTAssertNil(ModelDownloadBridge.progressFraction(progress))
    progress.totalUnitCount = 200
    progress.completedUnitCount = 37
    XCTAssertEqual(ModelDownloadBridge.progressFraction(progress), 0.185)
    progress.completedUnitCount = 200
    XCTAssertEqual(ModelDownloadBridge.progressFraction(progress), 1)
    progress.completedUnitCount = 250
    XCTAssertEqual(ModelDownloadBridge.progressFraction(progress), 1)
    progress.completedUnitCount = -1
    XCTAssertNil(ModelDownloadBridge.progressFraction(progress))
  }

  /// 网络等待必须区分无网络和仅有蜂窝网络，并且已启动任务不能放宽条件。
  func testNetworkPolicyDoesNotOfferMobileAfterStart() {
    let waiting = ModelDownloadBridge.networkEvent(
      model: "fr", wifiOnly: true, started: false, connected: true, wifi: false)
    XCTAssertEqual(waiting["phase"] as? String, "waitingWifi")
    XCTAssertEqual(waiting["canUseMobile"] as? Bool, true)
    let started = ModelDownloadBridge.networkEvent(
      model: "fr", wifiOnly: true, started: true, connected: true, wifi: false)
    XCTAssertEqual(started["phase"] as? String, "waitingWifi")
    XCTAssertEqual(started["canUseMobile"] as? Bool, false)
    let offline = ModelDownloadBridge.networkEvent(
      model: "fr", wifiOnly: true, started: false, connected: false, wifi: false)
    XCTAssertEqual(offline["phase"] as? String, "waitingNetwork")
    XCTAssertEqual(offline["canUseMobile"] as? Bool, false)
    let mobile = ModelDownloadBridge.networkEvent(
      model: "fr", wifiOnly: false, started: false, connected: true, wifi: false)
    XCTAssertEqual(mobile["phase"] as? String, "downloading")
    let wifi = ModelDownloadBridge.networkEvent(
      model: "fr", wifiOnly: true, started: false, connected: true, wifi: true)
    XCTAssertEqual(wifi["phase"] as? String, "downloading")
  }

  /// 通知通过 userInfo 的语言码路由，不能依赖通知 object 与请求实例相同。
  func testNotificationMatchesLanguageFromUserInfo() {
    let notification = Notification(
      name: .mlkitModelDownloadDidSucceed,
      object: NSObject(),
      userInfo: [ModelDownloadUserInfoKey.remoteModel.rawValue:
        TranslateRemoteModel.translateRemoteModel(language: .french)])
    XCTAssertEqual(ModelDownloadBridge.notificationModel(notification), "fr")
    XCTAssertNil(ModelDownloadBridge.notificationModel(
      Notification(name: .mlkitModelDownloadDidSucceed,
                   object: TranslateRemoteModel.translateRemoteModel(language: .french))))
  }

  /// 分类不能覆盖掉 ML Kit 外层原始 domain、code 和 message。
  func testUnderlyingNetworkErrorPreservesOriginalDetails() {
    let original = NSError(domain: "com.google.mlkit", code: 777, userInfo: [
      NSLocalizedDescriptionKey: "Original download failure",
      NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
    ])
    let mapped = ModelDownloadBridge.downloadError(original)
    XCTAssertEqual(mapped.code, "network")
    let details = mapped.details as? [String: Any]
    XCTAssertEqual(details?["domain"] as? String, "com.google.mlkit")
    XCTAssertEqual(details?["code"] as? Int, 777)
    XCTAssertEqual(details?["message"] as? String, "Original download failure")
    let underlying = details?["underlyingErrors"] as? [[String: Any]]
    XCTAssertEqual(underlying?.first?["domain"] as? String, NSURLErrorDomain)
    XCTAssertEqual(underlying?.first?["code"] as? Int, NSURLErrorTimedOut)
  }

  /// 覆盖存储、完整性、资源不可用及无法识别的错误，避免失败被吞掉。
  func testErrorCategoriesAndUnknownFallback() {
    let cases: [(NSError, String)] = [
      (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError), "storage"),
      (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), "storage"),
      (NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT)), "storage"),
      (NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotWriteToFile,
               userInfo: [NSLocalizedDescriptionKey: "Download failed: no space left on device"]), "storage"),
      (NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotDecodeContentData), "integrity"),
      (NSError(domain: NSURLErrorDomain, code: NSURLErrorResourceUnavailable), "unavailable"),
      (NSError(domain: "com.google.mlkit", code: 91,
               userInfo: [NSLocalizedDescriptionKey: "Model checksum mismatch"]), "integrity"),
      (NSError(domain: "future.sdk", code: 999,
               userInfo: [NSLocalizedDescriptionKey: "Opaque failure"]), "unknown"),
      (NSError(domain: NSPOSIXErrorDomain, code: Int.max,
               userInfo: [NSLocalizedDescriptionKey: "Future platform error"]), "unknown"),
    ]
    for (original, category) in cases {
      let mapped = ModelDownloadBridge.downloadError(original)
      XCTAssertEqual(mapped.code, category)
      XCTAssertEqual((mapped.details as? [String: Any])?["code"] as? Int, original.code)
      XCTAssertEqual(mapped.message, original.localizedDescription)
    }
  }

  /// 权限、只读及一般文件错误不能误导用户清理空间。
  func testPermissionAndGenericFileErrorsDoNotSuggestFreeSpace() {
    let cases: [(String, Int)] = [
      (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
      (NSCocoaErrorDomain, NSFileReadNoPermissionError),
      (NSCocoaErrorDomain, NSFileWriteVolumeReadOnlyError),
      (NSCocoaErrorDomain, NSFileWriteUnknownError),
      (NSPOSIXErrorDomain, Int(EACCES)),
      (NSPOSIXErrorDomain, Int(EPERM)),
      (NSPOSIXErrorDomain, Int(EROFS)),
      (NSPOSIXErrorDomain, Int(EIO)),
      (NSURLErrorDomain, NSURLErrorCannotOpenFile),
      (NSURLErrorDomain, NSURLErrorCannotCreateFile),
      (NSURLErrorDomain, NSURLErrorCannotWriteToFile),
      (NSURLErrorDomain, NSURLErrorCannotMoveFile),
    ]
    for (domain, code) in cases {
      let error = NSError(domain: domain, code: code)
      let mapped = ModelDownloadBridge.downloadError(error)
      XCTAssertEqual(mapped.code, "unknown", "Unexpected space warning for \(domain)/\(code)")
      let details = mapped.details as? [String: Any]
      XCTAssertEqual(details?["domain"] as? String, domain)
      XCTAssertEqual(details?["code"] as? Int, code)
      XCTAssertEqual(details?["message"] as? String, error.localizedDescription)
    }
  }

  /// SDK 包装的权限失败仍应保留底层原因，只有真实空间不足才建议释放空间。
  func testUnderlyingFileErrorDistinguishesPermissionFromOutOfSpace() {
    for (code, category) in [(EACCES, "unknown"), (ENOSPC, "storage")] {
      let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
      let original = NSError(domain: "com.google.mlkit", code: 777, userInfo: [
        NSLocalizedDescriptionKey: "Model download failed",
        NSUnderlyingErrorKey: underlying,
      ])
      let mapped = ModelDownloadBridge.downloadError(original)
      XCTAssertEqual(mapped.code, category)
      let details = mapped.details as? [String: Any]
      XCTAssertEqual(details?["domain"] as? String, "com.google.mlkit")
      XCTAssertEqual(details?["code"] as? Int, 777)
      XCTAssertEqual(mapped.message, "Model download failed")
      let chain = details?["underlyingErrors"] as? [[String: Any]]
      XCTAssertEqual(chain?.first?["domain"] as? String, NSPOSIXErrorDomain)
      XCTAssertEqual(chain?.first?["code"] as? Int, Int(code))
      XCTAssertEqual(chain?.first?["message"] as? String, underlying.localizedDescription)
    }
  }

}
