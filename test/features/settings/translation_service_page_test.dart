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
import 'package:xiaoan_tsl/services/translation/apple_translation_service.dart';
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
  test(
    'shared Apple preparation and error text is localized without exposing raw codes',
    () {
      for (final l10n in [
        const AppLocalizationsZh(),
        const AppLocalizationsEn(),
      ]) {
        expect(
          l10n.phasePreparingAppleTranslation,
          contains(l10n is AppLocalizationsZh ? '系统提示' : 'system prompts'),
        );
        for (final code in [
          'appleUnsupported',
          'appleUnsupportedLanguage',
          'appleCancelled',
          'applePreparationFailed',
          'applePreparationTimeout',
          'appleBusy',
          'appleTimeout',
          'appleInvalidArguments',
          'appleInvalidRequest',
          'appleTranslationFailed',
          'unknown',
        ]) {
          final message = l10n.appleTranslationError(code);
          expect(message, isNotEmpty);
          expect(message, isNot(contains(code)));
          expect(
            message,
            isNot(contains(l10n is AppLocalizationsZh ? '百度' : 'Baidu')),
          );
        }
        expect(
          l10n.appleTranslationError('applePreparationFailed'),
          isNot(l10n.appleTranslationError('appleTranslationFailed')),
        );
        expect(
          l10n.appleTranslationError('appleTimeout'),
          isNot(l10n.appleTranslationError('applePreparationTimeout')),
        );
      }
    },
  );

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
    Future<AppleTranslationAvailability> Function()? availability,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          translationPlatformProvider.overrideWithValue(platform),
          secureCredentialStoreProvider.overrideWithValue(credentials),
          dioProvider.overrideWithValue(dio ?? Dio()),
          if (availability != null)
            appleTranslationAvailabilityProvider.overrideWith(
              (_) => availability(),
            ),
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

  for (final platform in [
    TranslationPlatform.android,
    TranslationPlatform.ios,
  ]) {
    testWidgets('$platform 只显示 ML Kit 与百度，不显示苹果服务', (tester) async {
      await pumpPage(tester, platform: platform);
      expect(find.text('设备端离线翻译（ML Kit）'), findsOneWidget);
      expect(find.text('百度在线翻译'), findsOneWidget);
      expect(find.text('苹果离线翻译（macOS 15+）'), findsNothing);
    });
  }

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

  Finder appleTile() => find.byWidgetPredicate(
    (widget) => widget is RadioListTile<String> && widget.value == 'apple',
  );

  testWidgets('macOS 14 shows version reason and keeps saved apple', (
    tester,
  ) async {
    await tester.runAsync(
      () => store.setSetting(TranslationSettingKeys.engine, 'apple'),
    );
    await pumpPage(
      tester,
      platform: TranslationPlatform.macOS,
      availability: () async =>
          AppleTranslationAvailability.platformUnsupported,
    );
    expect(tester.widget<RadioListTile<String>>(appleTile()).enabled, isFalse);
    expect(find.text('需要 macOS 15 或更新版本'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => store.getSetting(TranslationSettingKeys.engine),
      ),
      'apple',
    );
    expect(find.byKey(const Key('baiduAppIdField')), findsNothing);
  });

  testWidgets(
    'apple availability loading disables selection without changing default',
    (tester) async {
      final completer = Completer<AppleTranslationAvailability>();
      await pumpPage(
        tester,
        platform: TranslationPlatform.macOS,
        availability: () => completer.future,
      );
      expect(find.text('正在检查苹果翻译可用性…'), findsOneWidget);
      expect(
        tester.widget<RadioListTile<String>>(appleTile()).enabled,
        isFalse,
      );
      expect(
        await tester.runAsync(
          () => store.getSetting(TranslationSettingKeys.engine),
        ),
        isNull,
      );
      completer.complete(AppleTranslationAvailability.supported);
      await settle(tester);
      expect(tester.widget<RadioListTile<String>>(appleTile()).enabled, isTrue);
    },
  );

  testWidgets('unsupported language pair is disabled with its own reason', (
    tester,
  ) async {
    await pumpPage(
      tester,
      platform: TranslationPlatform.macOS,
      availability: () async => AppleTranslationAvailability.unsupported,
    );
    expect(tester.widget<RadioListTile<String>>(appleTile()).enabled, isFalse);
    expect(find.text('此设备暂不支持英文与简体中文离线翻译'), findsOneWidget);
    expect(find.text('需要 macOS 15 或更新版本'), findsNothing);
  });

  testWidgets('availability failure retries and preserves saved apple', (
    tester,
  ) async {
    var checks = 0;
    await tester.runAsync(
      () => store.setSetting(TranslationSettingKeys.engine, 'apple'),
    );
    await pumpPage(
      tester,
      platform: TranslationPlatform.macOS,
      availability: () async {
        if (++checks == 1) {
          throw const AppleTranslationException('appleTranslationFailed');
        }
        return AppleTranslationAvailability.installed;
      },
    );
    expect(find.text('无法检查苹果翻译，请重试'), findsOneWidget);
    expect(find.text('需要 macOS 15 或更新版本'), findsNothing);
    expect(tester.widget<RadioListTile<String>>(appleTile()).enabled, isFalse);
    expect(
      await tester.runAsync(
        () => store.getSetting(TranslationSettingKeys.engine),
      ),
      'apple',
    );
    await tester.tap(find.byKey(const Key('retryAppleAvailability')));
    await settle(tester);
    expect(tester.widget<RadioListTile<String>>(appleTile()).enabled, isTrue);
    expect(find.text('系统语言包已安装'), findsOneWidget);
    expect(find.byKey(const Key('retryAppleAvailability')), findsNothing);
    expect(checks, 2);
  });

  testWidgets('mobile settings never invoke macOS channel', (tester) async {
    const channel = MethodChannel('xiaoan_tsl/macos_desktop');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'unexpectedChannelCall');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await pumpPage(tester, platform: TranslationPlatform.android);
    expect(appleTile(), findsNothing);
    expect(calls, isEmpty);
  });

  for (final status in [
    AppleTranslationAvailability.supported,
    AppleTranslationAvailability.installed,
  ]) {
    testWidgets(
      '$status selection persists apple, hides Baidu, retains credentials, never prepares',
      (tester) async {
        await credentials.writeBaiduCredentials(
          appId: 'kept-id',
          secret: 'kept-secret',
        );
        const channel = MethodChannel('xiaoan_tsl/macos_desktop');
        final calls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {'status': status.name};
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await pumpPage(tester, platform: TranslationPlatform.macOS);
        expect(
          tester.widget<RadioListTile<String>>(appleTile()).enabled,
          isTrue,
        );
        await tester.tap(appleTile());
        await settle(tester);
        expect(
          await tester.runAsync(
            () => store.getSetting(TranslationSettingKeys.engine),
          ),
          'apple',
        );
        expect(find.byKey(const Key('baiduAppIdField')), findsNothing);
        expect(find.byKey(const Key('baiduSecretField')), findsNothing);
        expect(find.byKey(const Key('testConnectionButton')), findsNothing);
        expect(find.text('首次准备需要联网下载语言包；翻译在设备端进行，语言包由系统管理。'), findsOneWidget);
        expect(await credentials.readBaiduAppId(), 'kept-id');
        expect(await credentials.readBaiduSecret(), 'kept-secret');
        expect(
          calls.every((call) => call.method == 'appleTranslationAvailability'),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        await pumpPage(tester, platform: TranslationPlatform.macOS);
        expect(
          ProviderScope.containerOf(
            tester.element(appleTile()),
          ).read(translationEngineProvider),
          'apple',
        );
        expect(find.byKey(const Key('baiduAppIdField')), findsNothing);
        await tester.tap(find.text('百度在线翻译'));
        await settle(tester);
        expect(find.byKey(const Key('baiduAppIdField')), findsOneWidget);
        expect(await credentials.hasBaiduCredentials(), isTrue);
      },
    );
  }

  for (final language in ['zh', 'en']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'apple $language $mode renders localized status and offline notice',
        (tester) async {
          await tester.runAsync(
            () => store.setSetting(TranslationSettingKeys.engine, 'apple'),
          );
          await pumpPage(
            tester,
            platform: TranslationPlatform.macOS,
            locale: Locale(language),
            themeMode: mode,
            availability: () async => AppleTranslationAvailability.supported,
          );
          expect(
            find.text(
              language == 'zh'
                  ? '支持，准备时由系统确认下载语言包'
                  : 'Supported; macOS will ask before downloading language packs',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              language == 'zh'
                  ? '首次准备需要联网下载语言包；翻译在设备端进行，语言包由系统管理。'
                  : 'The first preparation needs internet access to download language packs. Translation runs on-device; macOS manages the packs.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(
            Theme.of(tester.element(appleTile())).brightness,
            mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          );
        },
      );
    }
  }
}
