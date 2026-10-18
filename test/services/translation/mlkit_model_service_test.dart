import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/translation/mlkit_model_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_on_device_translator');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const downloadChannel = MethodChannel('xiaoan_tsl/model_download');
  final calls = <MethodCall>[];
  var downloadSucceeds = true;

  setUp(() {
    calls.clear();
    downloadSucceeds = true;
    messenger.setMockMethodCallHandler(downloadChannel, (call) async {
      calls.add(call);
      if (!downloadSucceeds) {
        throw PlatformException(
            code: 'storage',
            message: 'disk full',
            details: {'nativeCode': 101});
      }
      return 'success';
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final task = (call.arguments as Map)['task'];
      if (task == 'check') return false;
      if (task == 'download') return downloadSucceeds ? 'success' : 'failed';
      if (task == 'delete') return 'success';
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(downloadChannel, null);
  });

  test('查询、下载、删除使用真实模型代码且默认只允许 Wi-Fi', () async {
    final service = MlKitModelService();
    expect(await service.isDownloaded('en'), isFalse);
    await service.download('en');
    await service.delete('en');
    expect(
        calls.map((call) => (call.arguments as Map)['task'] ?? call.method), [
      'check',
      'download',
      'delete',
    ]);
    expect((calls[1].arguments as Map)['model'], 'en');
    expect((calls[1].arguments as Map)['wifiOnly'], isTrue);
  });

  test('下载失败抛出错误，不支持语言不进入插件', () async {
    final service = MlKitModelService();
    downloadSucceeds = false;
    await expectLater(
        service.download('zh'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'diagnostics', contains('disk full'))));
    calls.clear();
    await expectLater(service.isDownloaded('xx'), throwsArgumentError);
    expect(calls, isEmpty);
  });
  test('iOS 英语内置模型不进入远程模型插件，也不尝试删除', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = MlKitModelService();
    expect(await service.isDownloaded('en'), isTrue);
    await service.download('en');
    await service.delete('en');
    expect(calls, isEmpty);
  });
}
