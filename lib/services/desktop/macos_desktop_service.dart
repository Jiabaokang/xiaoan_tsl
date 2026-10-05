import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 桌面原生能力统一错误；取消不通过异常表达。
sealed class MacosDesktopException implements Exception {
  const MacosDesktopException(this.message);

  final String message;

  @override
  String toString() => message;
}

// 屏幕录制权限被拒绝或未授权。
class MacosDesktopPermissionException extends MacosDesktopException {
  const MacosDesktopPermissionException(super.message);
}

// 截图捕获失败。
class MacosDesktopCaptureException extends MacosDesktopException {
  const MacosDesktopCaptureException(super.message);
}

// OCR 识别失败。
class MacosDesktopOcrException extends MacosDesktopException {
  const MacosDesktopOcrException(super.message);
}

// 快捷键注册冲突。
class MacosDesktopShortcutConflictException extends MacosDesktopException {
  const MacosDesktopShortcutConflictException(super.message);
}

// 非 macOS 平台或通道未实现。
class MacosDesktopPlatformUnsupportedException extends MacosDesktopException {
  const MacosDesktopPlatformUnsupportedException(super.message);
}

// 一次截图会话的结果；cancelled 表示用户取消而非失败。
class CaptureRegionResult {
  const CaptureRegionResult({
    required this.requestId,
    required this.cancelled,
    this.pngBytes,
    this.displayId,
    this.selection,
    this.pixelWidth,
    this.pixelHeight,
  });

  final String requestId;

  // 用户按 Esc、空选区或 Dart 主动取消时为 true。
  final bool cancelled;

  // 裁剪后的 PNG 字节；取消时为空。
  final Uint8List? pngBytes;

  // 选区所在显示器的 CGDirectDisplayID。
  final int? displayId;

  // 选区（左下原点 point 坐标，与原生一致）。
  final Rect? selection;

  // 独立像素尺寸，不受窗口布局尺寸影响。
  final int? pixelWidth;
  final int? pixelHeight;
}

// 桌面事件（原生通知 Dart，不携带数据）。
enum MacosDesktopEvent {
  // 全局快捷键或菜单“截图翻译”触发。
  screenshotHotkey,

  // 菜单“设置”触发，Dart 导航到设置页。
  openSettings,
}

// 桌面能力边界；非 macOS 使用不支持实现，调用方不猜测平台。
abstract interface class MacosDesktopService {
  Future<CaptureRegionResult> captureRegion(String requestId);

  Future<String> recognizeText(String requestId, Uint8List pngBytes);

  Future<String?> identifyLanguage(String text);

  Future<void> showResultWindow({
    required int displayId,
    required Rect selection,
  });

  Future<void> cancelCapture(String requestId);

  // 注册全局截图快捷键；格式如 “Control+Option+T”。注册新键成功后才替换旧键。
  Future<void> updateShortcut(String shortcut);

  // 原生事件流：全局快捷键与菜单动作。
  Stream<MacosDesktopEvent> get events;
}

// 单个 MethodChannel 实现；通道只由目标平台处理。
class MacosDesktopChannel implements MacosDesktopService {
  MacosDesktopChannel({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('xiaoan_tsl/macos_desktop');

  static const _methodCapture = 'captureRegion';
  static const _methodRecognize = 'recognizeText';
  static const _methodIdentify = 'identifyLanguage';
  static const _methodShowResult = 'showResultWindow';
  static const _methodCancel = 'cancelCapture';
  static const _methodUpdateShortcut = 'updateShortcut';
  static const _eventChannelName = 'xiaoan_tsl/macos_desktop_events';

  final MethodChannel _channel;

  // 原生事件流；broadcast 允许页面与应用级监听各自订阅。
  late final Stream<MacosDesktopEvent> _events =
      const EventChannel(_eventChannelName).receiveBroadcastStream().map((event) {
    if (event == 'openSettings') return MacosDesktopEvent.openSettings;
    return MacosDesktopEvent.screenshotHotkey;
  });

  @override
  Stream<MacosDesktopEvent> get events => _events;

  @override
  Future<void> updateShortcut(String shortcut) async {
    try {
      await _channel.invokeMethod<void>(
        _methodUpdateShortcut,
        <String, Object>{'shortcut': shortcut},
      );
    } catch (error) {
      _throwMapped(error);
    }
  }

  @override
  Future<CaptureRegionResult> captureRegion(String requestId) async {
    final Map<Object?, Object?> map;
    try {
      map = await _invokeMap(
        _methodCapture,
        <String, Object>{'requestId': requestId},
      );
    } catch (error) {
      _throwMapped(error);
    }
    return CaptureRegionResult(
      requestId: map['requestId'] as String? ?? requestId,
      cancelled: map['cancelled'] as bool? ?? false,
      pngBytes: map['png'] as Uint8List?,
      displayId: map['displayId'] as int?,
      selection: map['x'] != null && map['y'] != null
          ? Rect.fromLTWH(
              (map['x'] as num).toDouble(),
              (map['y'] as num).toDouble(),
              (map['width'] as num).toDouble(),
              (map['height'] as num).toDouble(),
            )
          : null,
      pixelWidth: map['pixelWidth'] as int?,
      pixelHeight: map['pixelHeight'] as int?,
    );
  }

  @override
  Future<String> recognizeText(
    String requestId,
    Uint8List pngBytes,
  ) async {
    final String? text;
    try {
      text = await _channel.invokeMethod<String>(
        _methodRecognize,
        <String, Object>{'requestId': requestId, 'png': pngBytes},
      );
    } catch (error) {
      _throwMapped(error);
    }
    return text ?? '';
  }

  @override
  Future<String?> identifyLanguage(String text) async {
    final String? code;
    try {
      code = await _channel.invokeMethod<String>(
        _methodIdentify,
        <String, Object>{'text': text},
      );
    } catch (error) {
      _throwMapped(error);
    }
    return code;
  }

  @override
  Future<void> showResultWindow({
    required int displayId,
    required Rect selection,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        _methodShowResult,
        <String, Object>{
          'displayId': displayId,
          'x': selection.left,
          'y': selection.top,
          'width': selection.width,
          'height': selection.height,
        },
      );
    } catch (error) {
      _throwMapped(error);
    }
  }

  @override
  Future<void> cancelCapture(String requestId) async {
    try {
      await _channel.invokeMethod<void>(
        _methodCancel,
        <String, Object>{'requestId': requestId},
      );
    } catch (error) {
      _throwMapped(error);
    }
  }

  Future<Map<Object?, Object?>> _invokeMap(
    String method,
    Map<String, Object> arguments,
  ) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      method,
      arguments,
    );
    return result ?? const {};
  }

  // 把原生错误码映射为领域异常；未知错误原样抛出。
  Never _throwMapped(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'permissionDenied':
          throw MacosDesktopPermissionException(error.message ?? '屏幕录制权限被拒绝');
        case 'captureFailed':
          throw MacosDesktopCaptureException(error.message ?? '截图失败');
        case 'ocrFailed':
          throw MacosDesktopOcrException(error.message ?? 'OCR 识别失败');
        case 'shortcutConflict':
          throw MacosDesktopShortcutConflictException(error.message ?? '快捷键注册冲突');
        case 'platformUnsupported':
          throw MacosDesktopPlatformUnsupportedException(error.message ?? '平台不支持该能力');
      }
    }
    if (error is MissingPluginException) {
      throw const MacosDesktopPlatformUnsupportedException('桌面通道未注册');
    }
    throw error;
  }
}

// 非 macOS 的明确不支持实现，不触达任何原生通道。
class MacosDesktopUnsupportedService implements MacosDesktopService {
  @override
  Future<CaptureRegionResult> captureRegion(String requestId) async {
    throw const MacosDesktopPlatformUnsupportedException(
      '当前平台不支持桌面截图能力',
    );
  }

  @override
  Future<String> recognizeText(String requestId, Uint8List pngBytes) async {
    throw const MacosDesktopPlatformUnsupportedException(
      '当前平台不支持桌面截图能力',
    );
  }

  @override
  Future<String?> identifyLanguage(String text) async => null;

  @override
  Future<void> showResultWindow({
    required int displayId,
    required Rect selection,
  }) async {
    throw const MacosDesktopPlatformUnsupportedException(
      '当前平台不支持桌面截图能力',
    );
  }

  @override
  Future<void> cancelCapture(String requestId) async {}

  @override
  Future<void> updateShortcut(String shortcut) async {
    throw const MacosDesktopPlatformUnsupportedException(
      '当前平台不支持桌面截图能力',
    );
  }

  @override
  Stream<MacosDesktopEvent> get events => const Stream.empty();
}

// 桌面服务实例；macOS 使用通道，其他平台返回不支持实现。
final macosDesktopServiceProvider = Provider<MacosDesktopService>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    return MacosDesktopChannel();
  }
  return MacosDesktopUnsupportedService();
});
