import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoan_tsl/core/database/database_provider.dart';
import 'package:xiaoan_tsl/core/database/local_store.dart';
import 'package:xiaoan_tsl/core/network/dio_provider.dart';
import 'package:xiaoan_tsl/core/theme/app_theme.dart';
import 'package:xiaoan_tsl/features/settings/translation_service_page.dart';
import 'package:xiaoan_tsl/l10n/app_localizations.dart';
import 'package:xiaoan_tsl/services/translation/translation_service_provider.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';

// 内存凭据替身：验证页面读写不触碰系统 Keychain。
class _MemoryCredentials implements SecureCredentialStore {
  String? appId;
  String? secret;
  String? failingOperation;

  // 模拟原生钥匙串异常，覆盖页面恢复行为，错误消息不展示给用户。
  void _checkFailure(String operation) {
    if (failingOperation == operation) {
      throw PlatformException(
        code: 'Unexpected security result code',
        details: -34018,
      );
    }
  }

  @override
  Future<String?> readBaiduAppId() async => appId;

  @override
  Future<String?> readBaiduSecret() async => secret;

  @override
  Future<bool> hasBaiduCredentials() async {
    _checkFailure('read');
    return appId != null &&
        appId!.isNotEmpty &&
        secret != null &&
        secret!.isNotEmpty;
  }

  @override
  Future<void> writeBaiduCredentials({
    required String appId,
    required String secret,
  }) async {
    _checkFailure('write');
    this.appId = appId;
    this.secret = secret;
  }

  @override
  Future<void> deleteBaiduCredentials() async {
    _checkFailure('delete');
    appId = null;
    secret = null;
  }
}

// 固定返回成功译文的适配器，用于“测试连接”在线请求。
class _SuccessAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await for (final _ in requestStream ?? const Stream<Uint8List>.empty()) {}
    return ResponseBody.fromString(
      jsonEncode({
        'trans_result': [
          {'src': 'Hello, world!', 'dst': '你好，世界！'},
        ],
      }),
      200,
      headers: const {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// 固定返回业务错误的适配器，验证失败时保留输入。
class _ErrorAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await for (final _ in requestStream ?? const Stream<Uint8List>.empty()) {}
    return ResponseBody.fromString(
      jsonEncode({'error_code': '54004', 'error_msg': '余额不足'}),
      200,
      headers: const {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late LocalStore store;
  late _MemoryCredentials credentials;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xiaoan_service_page_');
    store = await LocalStore.open(
      path: path.join(directory.path, 'app.db'),
      legacyFile: File(path.join(directory.path, 'none.json')),
      factory: databaseFactoryFfi,
    );
    credentials = _MemoryCredentials();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  // 让真实异步（sqflite/keychain 替身）完成后再刷新界面。
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required TranslationPlatform platform,
    Dio? dio,
    Locale locale = const Locale('zh'),
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          translationPlatformProvider.overrideWithValue(platform),
          secureCredentialStoreProvider.overrideWithValue(credentials),
          dioProvider.overrideWithValue(dio ?? Dio()),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: themeMode,
          home: const TranslationServicePage(),
        ),
      ),
    );
    // 页面初始化会读取安全存储与 SQLite，真实异步需要 runAsync 完成。
    await settle(tester);
  }

  testWidgets('移动端显示 ML Kit 与百度，苹果服务禁用', (tester) async {
    await pumpPage(tester, platform: TranslationPlatform.android);
    expect(find.text('设备端离线翻译（ML Kit）'), findsOneWidget);
    expect(find.text('百度在线翻译'), findsOneWidget);
    final apple = tester.widget<RadioListTile<String>>(
      find.byWidgetPredicate(
        (widget) => widget is RadioListTile<String> && widget.value == 'apple',
      ),
    );
    expect(apple.enabled, isFalse);
  });

  testWidgets('macOS 不显示 ML Kit，快捷键入口移至设置主页', (tester) async {
    await pumpPage(tester, platform: TranslationPlatform.macOS);
    expect(find.text('设备端离线翻译（ML Kit）'), findsNothing);
    expect(find.text('百度在线翻译'), findsOneWidget);
    expect(find.byKey(const Key('screenshotShortcutTile')), findsNothing);
  });

  testWidgets('密钥输入框默认掩码显示', (tester) async {
    await pumpPage(tester, platform: TranslationPlatform.macOS);
    final field = tester.widget<TextField>(
      find.byKey(const Key('baiduSecretField')),
    );
    expect(field.obscureText, isTrue);
  });

  testWidgets('空凭据保存提示填写 AppID 和密钥', (tester) async {
    await pumpPage(tester, platform: TranslationPlatform.macOS);
    await tester.tap(find.text('保存凭据'));
    await settle(tester);
    expect(find.text('请填写 AppID 和密钥'), findsOneWidget);
  });

  testWidgets('保存凭据写入安全存储并清空输入', (tester) async {
    await pumpPage(tester, platform: TranslationPlatform.macOS);
    await tester.enterText(find.byKey(const Key('baiduAppIdField')), 'app-123');
    await tester.enterText(
      find.byKey(const Key('baiduSecretField')),
      'secret-456',
    );
    await tester.tap(find.text('保存凭据'));
    await settle(tester);

    expect(await credentials.readBaiduAppId(), 'app-123');
    expect(await credentials.readBaiduSecret(), 'secret-456');
    expect(find.text('凭据已保存'), findsOneWidget);
    final appIdField = tester.widget<TextField>(
      find.byKey(const Key('baiduAppIdField')),
    );
    expect(appIdField.controller!.text, isEmpty);
  });

  testWidgets('保存凭据异常保留输入、恢复按钮并允许重试', (tester) async {
    await pumpPage(tester, platform: TranslationPlatform.macOS);
    await tester.enterText(find.byKey(const Key('baiduAppIdField')), 'app-123');
    await tester.enterText(
      find.byKey(const Key('baiduSecretField')),
      'secret-456',
    );
    credentials.failingOperation = 'write';
    await tester.tap(find.text('保存凭据'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('无法访问安全存储，请检查系统钥匙串后重试'), findsOneWidget);
    expect(find.text('凭据已保存'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('baiduAppIdField')))
          .controller!
          .text,
      'app-123',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('baiduSecretField')))
          .controller!
          .text,
      'secret-456',
    );
    credentials.failingOperation = null;
    await tester.tap(find.text('保存凭据'));
    await settle(tester);
    expect(find.text('凭据已保存'), findsOneWidget);
  });

  testWidgets('初始化读取凭据失败显示提示且页面可继续操作', (tester) async {
    credentials.failingOperation = 'read';
    await pumpPage(tester, platform: TranslationPlatform.macOS);
    expect(tester.takeException(), isNull);
    expect(find.text('无法访问安全存储，请检查系统钥匙串后重试'), findsOneWidget);
  });

  testWidgets('删除凭据异常保留已配置状态且允许重试', (tester) async {
    await credentials.writeBaiduCredentials(appId: 'a', secret: 'b');
    await pumpPage(tester, platform: TranslationPlatform.macOS);
    credentials.failingOperation = 'delete';
    await tester.tap(find.text('删除凭据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除凭据').last);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('无法访问安全存储，请检查系统钥匙串后重试'), findsOneWidget);
    expect(find.text('凭据已删除'), findsNothing);
    expect(await credentials.hasBaiduCredentials(), isTrue);
    credentials.failingOperation = null;
    await tester.tap(find.text('删除凭据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除凭据').last);
    await settle(tester);
    expect(find.text('凭据已删除'), findsOneWidget);
  });

  testWidgets('删除凭据需确认并清空安全存储', (tester) async {
    await credentials.writeBaiduCredentials(appId: 'a', secret: 'b');
    await pumpPage(tester, platform: TranslationPlatform.macOS);

    await tester.tap(find.text('删除凭据'));
    await tester.pumpAndSettle();
    expect(find.text('删除凭据？'), findsOneWidget);
    await tester.tap(find.text('删除凭据').last);
    await settle(tester);

    expect(await credentials.hasBaiduCredentials(), isFalse);
    expect(find.text('凭据已删除'), findsOneWidget);
  });

  testWidgets('测试连接成功显示连接正常', (tester) async {
    await credentials.writeBaiduCredentials(appId: 'a', secret: 'b');
    final dio = Dio()..httpClientAdapter = _SuccessAdapter();
    await pumpPage(tester, platform: TranslationPlatform.macOS, dio: dio);

    await tester.tap(find.byKey(const Key('testConnectionButton')));
    await tester.pumpAndSettle();
    expect(find.text('发送测试请求？'), findsOneWidget);
    await tester.tap(find.text('测试连接').last);
    await settle(tester);

    expect(find.text('连接正常'), findsOneWidget);
    expect(find.byKey(const Key('testError')), findsNothing);
  });

  testWidgets('测试连接失败保留输入并显示错误', (tester) async {
    await credentials.writeBaiduCredentials(appId: 'a', secret: 'b');
    final dio = Dio()..httpClientAdapter = _ErrorAdapter();
    await pumpPage(tester, platform: TranslationPlatform.macOS, dio: dio);

    await tester.tap(find.byKey(const Key('testConnectionButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试连接').last);
    await settle(tester);

    expect(find.byKey(const Key('testError')), findsOneWidget);
    expect(find.textContaining('额度不足'), findsOneWidget);
  });

  testWidgets('英文与暗色主题下正常渲染', (tester) async {
    await pumpPage(
      tester,
      platform: TranslationPlatform.macOS,
      locale: const Locale('en'),
      themeMode: ThemeMode.dark,
    );
    expect(find.text('Translation Service'), findsOneWidget);
    expect(find.text('Baidu Online Translation'), findsOneWidget);
    expect(find.text('Screenshot Shortcut'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
