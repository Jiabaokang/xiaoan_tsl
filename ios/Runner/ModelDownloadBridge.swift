import Darwin
import Flutter
import MLKitCommon
import MLKitTranslate
import Network

/// 使用现有 ML Kit 模型存储，向 Flutter 提供下载策略、真实进度和最终结果。
final class ModelDownloadBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let modelManager = ModelManager.modelManager()
  /// 所有下载状态和 Flutter 回调仅在主队列读写，同一语言共享一个 SDK 任务。
  private var pending: [String: PendingModelDownload] = [:]
  private var eventSink: FlutterEventSink?
  /// 只有收到监视器的实际路径回调后才能启动下载，不能假定初始路径可用。
  private var monitor: NWPathMonitor?
  private var path: NWPath?
  private var detached = false

  /// 发布实例后 Flutter 才会在引擎移除插件时调用 detachFromEngine。
  init(registrar: FlutterPluginRegistrar) {
    methodChannel = FlutterMethodChannel(
      name: "xiaoan_tsl/model_download", binaryMessenger: registrar.messenger())
    eventChannel = FlutterEventChannel(
      name: "xiaoan_tsl/model_download_events", binaryMessenger: registrar.messenger())
    super.init()
    registrar.addMethodCallDelegate(self, channel: methodChannel)
    registrar.publish(self)
    eventChannel.setStreamHandler(self)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    _ = ModelDownloadBridge(registrar: registrar)
  }

  /// 仅接管下载与策略调整；模型查询和删除继续使用已有插件。
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !detached else {
      result(FlutterError(code: "detached", message: "Download bridge detached", details: nil))
      return
    }
    guard call.method == "download" || call.method == "allowMobileData" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let model = args["model"] as? String, !model.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Missing model language code", details: nil))
      return
    }
    if call.method == "allowMobileData" {
      guard let download = pending[model], !download.started, download.wifiOnly,
            download.lastEvent?["phase"] as? String == "waitingWifi" else {
        result(FlutterError(code: "invalid_state",
                            message: "Only an unstarted waitingWifi download can use mobile data",
                            details: ["model": model]))
        return
      }
      download.wifiOnly = false
      result(nil)
      update(download)
      return
    }
    guard let wifiOnly = args["wifiOnly"] as? Bool else {
      result(FlutterError(code: "invalid_args", message: "Missing wifiOnly boolean", details: nil))
      return
    }
    if let download = pending[model] {
      // 重复请求不能暗中放宽最初策略，只能通过 allowMobileData 显式调整。
      download.results.append(result)
      emit(download, replay: true)
      return
    }
    let language = TranslateLanguage(rawValue: model)
    guard TranslateLanguage.allLanguages().contains(language) else {
      result(FlutterError(code: "unavailable", message: "Unsupported translation model",
                          details: ["model": model]))
      return
    }
    // 官方声明英语内置，要求勿创建其远程模型，且该实例不能下载或删除。
    // https://developers.google.com/ml-kit/reference/ios/mlkittranslate/api/reference/Classes/MLKTranslateRemoteModel
    if language == .english {
      result("success")
      return
    }
    let remoteModel = TranslateRemoteModel.translateRemoteModel(language: language)
    if modelManager.isModelDownloaded(remoteModel) {
      result("success")
      return
    }
    let download = PendingModelDownload(model: remoteModel, wifiOnly: wifiOnly, result: result)
    pending[model] = download
    startMonitoringIfNeeded()
    update(download)
  }

  /// 新的监听者立即取得仍在等待或下载的状态，取消监听不取消 SDK 任务。
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    eventSink = events
    for download in Array(pending.values) { emit(download, replay: true) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  /// 监视器和下载回调共用主队列，避免重复启动及策略切换竞态。
  private func startMonitoringIfNeeded() {
    guard monitor == nil else { return }
    let monitor = NWPathMonitor()
    self.monitor = monitor
    monitor.pathUpdateHandler = { [weak self, weak monitor] path in
      guard let self = self, let monitor = monitor, self.monitor === monitor else { return }
      self.path = path
      for download in Array(self.pending.values) { self.update(download) }
    }
    monitor.start(queue: .main)
  }

  /// 启动后只更新等待状态，绝不取消或重新发起条件不可变的 SDK 下载。
  private func update(_ download: PendingModelDownload) {
    guard pending[download.code] === download else { return }
    let connected = path?.status == .satisfied
    let wifi = path?.usesInterfaceType(.wifi) == true
    if !download.started && connected && (!download.wifiOnly || wifi) {
      start(download)
    }
    if pending[download.code] === download { emit(download) }
  }

  /// 在调用 SDK 前注册通知，以覆盖 SDK 同步完成或很快失败的情况。
  private func start(_ download: PendingModelDownload) {
    download.started = true
    for name in [Notification.Name.mlkitModelDownloadDidSucceed, .mlkitModelDownloadDidFail] {
      let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self, weak download] notification in
        guard let self = self, let download = download,
              self.pending[download.code] === download,
              Self.notificationModel(notification) == download.code else { return }
        if notification.name == .mlkitModelDownloadDidSucceed {
          self.complete(download, value: "success")
        } else {
          // SDK 头文件规定原始 NSError 位于 userInfo，不能用固定错误覆盖它。
          let error = notification.userInfo?[ModelDownloadUserInfoKey.error.rawValue] as? NSError
            ?? NSError(domain: "xiaoan_tsl.model_download", code: 0, userInfo: [
              NSLocalizedDescriptionKey: "ML Kit failure notification contained no NSError",
            ])
          self.complete(download, value: Self.downloadError(error))
        }
      }
      download.observers.append(token)
    }
    let progress = modelManager.download(
      download.model, conditions: Self.downloadConditions(wifiOnly: download.wifiOnly))
    guard pending[download.code] === download else { return }
    download.progress = progress
    // 总量可能稍后才确定；同时观察总量与真实 fraction，绝不用计时器模拟进度。
    download.observations = [
      progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self, weak download] _, _ in
        self?.progressChanged(download)
      },
      progress.observe(\.totalUnitCount, options: [.new]) { [weak self, weak download] _, _ in
        self?.progressChanged(download)
      },
    ]
  }

  /// KVO 可能来自后台线程，发送前再次核对任务是否仍然有效。
  private func progressChanged(_ download: PendingModelDownload?) {
    DispatchQueue.main.async { [weak self, weak download] in
      guard let self = self, let download = download,
            self.pending[download.code] === download else { return }
      self.emit(download)
    }
  }

  private func emit(_ download: PendingModelDownload, replay: Bool = false) {
    var event = Self.networkEvent(model: download.code, wifiOnly: download.wifiOnly,
                                 started: download.started, connected: path?.status == .satisfied,
                                 wifi: path?.usesInterfaceType(.wifi) == true)
    if let progress = download.progress, let fraction = Self.progressFraction(progress) {
      event["progress"] = fraction
    }
    let changed = !NSDictionary(dictionary: event).isEqual(to: download.lastEvent ?? [:])
    download.lastEvent = event
    if changed || replay { eventSink?(event) }
  }

  /// 先释放每个任务的观察资源和状态，再一次性结束所有合并的请求。
  private func complete(_ download: PendingModelDownload, value: Any) {
    guard pending[download.code] === download else { return }
    pending.removeValue(forKey: download.code)
    download.cleanObservers()
    let results = download.results
    download.results.removeAll()
    if pending.isEmpty { stopMonitoring() }
    for result in results { result(value) }
  }

  private func stopMonitoring() {
    monitor?.pathUpdateHandler = nil
    monitor?.cancel()
    monitor = nil
    path = nil
  }

  /// 引擎分离只终止桥接回调与观察，不声称已取消仍由 SDK 管理的下载。
  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    detach()
  }

  private func detach() {
    guard !detached else { return }
    detached = true
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
    eventSink = nil
    stopMonitoring()
    let downloads = Array(pending.values)
    pending.removeAll()
    for download in downloads {
      download.cleanObservers()
      let results = download.results
      download.results.removeAll()
      for result in results {
        result(FlutterError(code: "detached", message: "Engine detached during model download",
                            details: ["model": download.code]))
      }
    }
  }

  deinit { detach() }

  /// Wi-Fi 限制必须同时交给 ML Kit 执行，防止启动后网络切换时使用蜂窝流量。
  static func downloadConditions(wifiOnly: Bool) -> ModelDownloadConditions {
    ModelDownloadConditions(allowsCellularAccess: !wifiOnly, allowsBackgroundDownloading: true)
  }

  /// 只公开 SDK 已知总量下的有限分数；分数到 1 仍须等待成功通知。
  static func progressFraction(_ progress: Progress) -> Double? {
    guard progress.totalUnitCount > 0, progress.completedUnitCount >= 0 else { return nil }
    let fraction = progress.fractionCompleted
    guard fraction.isFinite, fraction >= 0 else { return nil }
    return min(fraction, 1)
  }

  /// 仅尚未启动且正在等待 Wi-Fi 的请求可提供使用移动网络选项。
  static func networkEvent(model: String, wifiOnly: Bool, started: Bool,
                           connected: Bool, wifi: Bool) -> [String: Any] {
    let phase = !connected ? "waitingNetwork" : (wifiOnly && !wifi ? "waitingWifi" : "downloading")
    return ["model": model, "phase": phase,
            "canUseMobile": !started && wifiOnly && phase == "waitingWifi"]
  }

  /// 官方通知携带的模型可以是另一个实例，使用语言而非对象身份匹配。
  static func notificationModel(_ notification: Notification) -> String? {
    (notification.userInfo?[ModelDownloadUserInfoKey.remoteModel.rawValue]
      as? TranslateRemoteModel)?.language.rawValue
  }

  /// 保留原始 SDK 错误及底层错误链；不猜测 ML Kit 未公开的数字错误码含义。
  static func downloadError(_ error: NSError) -> FlutterError {
    var errors: [NSError] = []
    var current: NSError? = error
    var visited: Set<ObjectIdentifier> = []
    while let value = current, errors.count < 16, visited.insert(ObjectIdentifier(value)).inserted {
      errors.append(value)
      current = value.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    let category = errors.lazy.compactMap { errorCategory($0) }.first ?? "unknown"
    var details: [String: Any] = errorDetails(error)
    if errors.count > 1 { details["underlyingErrors"] = errors.dropFirst().map { errorDetails($0) } }
    return FlutterError(code: category, message: error.localizedDescription, details: details)
  }

  private static func errorDetails(_ error: NSError) -> [String: Any] {
    ["domain": error.domain, "code": error.code, "message": error.localizedDescription]
  }

  /// storage 专指空间或配额不足；权限、只读和一般文件错误保留为未知原因。
  private static func errorCategory(_ error: NSError) -> String? {
    if error.domain == NSURLErrorDomain {
      switch error.code {
      case NSURLErrorCannotDecodeRawData, NSURLErrorCannotDecodeContentData: return "integrity"
      case NSURLErrorResourceUnavailable, NSURLErrorFileDoesNotExist: return "unavailable"
      case NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
           NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
           NSURLErrorNotConnectedToInternet, NSURLErrorInternationalRoamingOff,
           NSURLErrorCallIsActive, NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed:
        return "network"
      default: break
      }
    }
    if error.domain == NSCocoaErrorDomain {
      switch error.code {
      case NSFileWriteOutOfSpaceError: return "storage"
      case NSFileReadCorruptFileError: return "integrity"
      default: break
      }
    }
    if error.domain == NSPOSIXErrorDomain {
      switch error.code {
      case Int(ENOSPC), Int(EDQUOT): return "storage"
      case Int(ENETDOWN), Int(ENETUNREACH), Int(ENOTCONN), Int(ECONNRESET), Int(ECONNREFUSED),
           Int(ETIMEDOUT): return "network"
      default: break
      }
    }
    let message = error.localizedDescription.lowercased()
    if ["checksum", "hash mismatch", "corrupt", "invalid model", "failed to validate model"]
      .contains(where: message.contains) { return "integrity" }
    if ["not enough space", "no space left", "insufficient storage", "disk full"]
      .contains(where: message.contains) { return "storage" }
    if ["model not found", "model is not available", "unsupported language", "unsupported model"]
      .contains(where: message.contains) { return "unavailable" }
    if ["network error", "network connection", "internet connection", "timed out"]
      .contains(where: message.contains) { return "network" }
    return nil
  }
}

/// 保存单个语言的等待策略与 SDK 任务资源，完成时统一释放所有观察者。
private final class PendingModelDownload {
  let model: TranslateRemoteModel
  var code: String { model.language.rawValue }
  /// 启动后不再修改策略，防止把界面授权误当成 SDK 下载条件已经变化。
  var wifiOnly: Bool
  var started = false
  var results: [FlutterResult]
  var progress: Progress?
  var observations: [NSKeyValueObservation] = []
  var observers: [NSObjectProtocol] = []
  var lastEvent: [String: Any]?

  init(model: TranslateRemoteModel, wifiOnly: Bool, result: @escaping FlutterResult) {
    self.model = model
    self.wifiOnly = wifiOnly
    results = [result]
  }

  /// 不调用 Progress.cancel()，清理观察者不等于取消底层下载。
  func cleanObservers() {
    for observation in observations { observation.invalidate() }
    observations.removeAll()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    progress = nil
  }

  deinit { cleanObservers() }
}
