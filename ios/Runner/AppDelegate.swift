import Flutter
import UIKit

/// 初始化 Flutter 隐式引擎，并持有与该引擎绑定的原生模型下载桥接。
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 保持桥接存活，避免下载尚未完成时观察者和 Flutter 回调被释放。
  private var modelDownloadBridge: ModelDownloadBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 从当前引擎的注册表获取 registrar，确保通道绑定到正确的 FlutterEngine。
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ModelDownloadBridge") {
      modelDownloadBridge = ModelDownloadBridge(registrar: registrar)
    }
  }
}
