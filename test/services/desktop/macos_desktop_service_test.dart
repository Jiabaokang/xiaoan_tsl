import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/desktop/macos_desktop_service.dart';

// 桌面通道替身：记录调用并返回可控结果或抛错。
class _ChannelStub {
  _ChannelStub(this.handler);

  Future<Object?> Function(
    MethodCall call,
  ) handler;

  final calls = <MethodCall>[];
  String? lastRequestId;

  Future<Object?> onCall(MethodCall call) async {
    calls.add(call);
    if (call.method == 'captureRegion') {
      lastRequestId = call.arguments['requestId'] as String;
    }
    return handler(call);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('xiaoan_tsl/macos_desktop');
  late _ChannelStub stub;

  setUp(() {
    stub = _ChannelStub((call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, stub.onCall);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('captureRegion 解析 requestId、PNG、displayId、选区与像素尺寸', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => <Object?, Object?>{
          'requestId': 'req-1',
          'cancelled': false,
          'png': Uint8List.fromList([1, 2, 3]),
          'displayId': 1001,
          'x': -120.0,
          'y': 40.0,
          'width': 640.0,
          'height': 200.0,
          'pixelWidth': 2560,
          'pixelHeight': 800,
        };

    final result = await service.captureRegion('req-1');
    expect(stub.lastRequestId, 'req-1');
    expect(result.requestId, 'req-1');
    expect(result.cancelled, isFalse);
    expect(result.pngBytes, Uint8List.fromList([1, 2, 3]));
    expect(result.displayId, 1001);
    expect(result.selection!.left, -120.0);
    expect(result.selection!.top, 40.0);
    expect(result.selection!.width, 640.0);
    expect(result.selection!.height, 200.0);
    expect(result.pixelWidth, 2560);
    expect(result.pixelHeight, 800);
  });

  test('captureRegion 取消返回 cancelled 而不是异常', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => <Object?, Object?>{
          'requestId': 'req-2',
          'cancelled': true,
        };

    final result = await service.captureRegion('req-2');
    expect(result.cancelled, isTrue);
    expect(result.pngBytes, isNull);
  });

  test('权限错误映射为 permissionDenied 异常', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async {
      throw PlatformException(code: 'permissionDenied', message: '无权限');
    };

    await expectLater(
      service.captureRegion('req-3'),
      throwsA(isA<MacosDesktopPermissionException>()),
    );
  });

  test('截图失败映射为 captureFailed 异常', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async {
      throw PlatformException(code: 'captureFailed', message: '捕获失败');
    };

    await expectLater(
      service.captureRegion('req-4'),
      throwsA(isA<MacosDesktopCaptureException>()),
    );
  });

  test('recognizeText 传入 requestId 与 PNG，并返回识别文字', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => '你好，世界';
    final png = Uint8List.fromList([9, 9, 9]);

    final text = await service.recognizeText('req-5', png);
    expect(text, '你好，世界');
    expect(stub.calls.single.method, 'recognizeText');
    expect(stub.calls.single.arguments['requestId'], 'req-5');
    expect(stub.calls.single.arguments['png'], png);
  });

  test('OCR 失败映射为 ocrFailed 异常', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async {
      throw PlatformException(code: 'ocrFailed', message: '识别失败');
    };

    await expectLater(
      service.recognizeText('req-6', Uint8List(0)),
      throwsA(isA<MacosDesktopOcrException>()),
    );
  });

  test('identifyLanguage 返回标准代码或 null', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => 'en';
    expect(await service.identifyLanguage('hello'), 'en');

    stub.handler = (call) async => null;
    expect(await service.identifyLanguage('不确定'), isNull);
  });

  test('showResultWindow 传递 displayId 与选区坐标', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => null;

    await service.showResultWindow(
      displayId: 2001,
      selection: const Rect.fromLTWH(10, 20, 300, 120),
    );
    final args = stub.calls.single.arguments as Map<Object?, Object?>;
    expect(args['displayId'], 2001);
    expect(args['x'], 10);
    expect(args['y'], 20);
    expect(args['width'], 300);
    expect(args['height'], 120);
  });

  test('cancelCapture 只传递 requestId，不抛异常', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => null;

    await service.cancelCapture('req-7');
    expect(stub.calls.single.method, 'cancelCapture');
    expect(stub.calls.single.arguments['requestId'], 'req-7');
  });

  test('updateShortcut 传递快捷键配置', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => null;

    await service.updateShortcut('Control+Shift+T');
    expect(stub.calls.single.method, 'updateShortcut');
    expect(stub.calls.single.arguments['shortcut'], 'Control+Shift+T');
  });

  test('空快捷键表示关闭全局快捷键', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async => null;

    await service.updateShortcut('');
    expect(stub.calls.single.arguments['shortcut'], '');
  });

  test('快捷键冲突映射为 shortcutConflict 异常', () async {
    final service = MacosDesktopChannel();
    stub.handler = (call) async {
      throw PlatformException(code: 'shortcutConflict', message: '与其他应用冲突');
    };

    await expectLater(
      service.updateShortcut('Control+Option+T'),
      throwsA(isA<MacosDesktopShortcutConflictException>()),
    );
  });

  test('系统关闭结果窗口的事件不能被误当成新的截图', () async {
    final service = MacosDesktopChannel();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final eventChannel = EventChannel('xiaoan_tsl/macos_desktop_events');
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success('screenshotHotkey');
          events.success('openSettings');
          events.success('dismissScreenshot');
          events.success('confirmScreenshot');
          events.success('retryScreenshot');
          events.success('openTranslationSettings');
        },
      ),
    );
    final received = <MacosDesktopEvent>[];
    final subscription = service.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(received.map((event) => event.name), [
      'screenshotHotkey',
      'openSettings',
      'dismissScreenshot',
      'confirmScreenshot',
      'retryScreenshot',
      'openTranslationSettings',
    ]);
  });

  test('非 macOS 平台守卫返回不支持实现并抛出明确异常', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(macosDesktopServiceProvider);
    expect(service, isA<MacosDesktopUnsupportedService>());
    await expectLater(
      service.captureRegion('req-8'),
      throwsA(isA<MacosDesktopPlatformUnsupportedException>()),
    );
    await expectLater(
      service.updateShortcut('Control+Option+T'),
      throwsA(isA<MacosDesktopPlatformUnsupportedException>()),
    );
  });

  test('macOS 平台守卫返回通道实现', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(macosDesktopServiceProvider);
    expect(service, isA<MacosDesktopChannel>());
  });
}
