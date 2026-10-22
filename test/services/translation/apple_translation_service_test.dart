import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/translation/apple_translation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/apple_translation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AppleTranslationService service;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    service = AppleTranslationService(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'appleTranslationAvailability' => {'status': 'installed'},
        'translateText' => {
          'requestId': (call.arguments as Map)['requestId'],
          'translatedText': '你好',
        },
        _ => null,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<String> translate({String? requestId, String text = 'Hello'}) =>
      service.translate(
        text: text,
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        requestId: requestId,
      );

  TypeMatcher<AppleTranslationException> code(String expected) =>
      isA<AppleTranslationException>().having(
        (error) => error.code,
        'code',
        expected,
      );

  test('apple_requires_no_mlkit_models', () {
    expect(service.engineId, 'apple');
    expect(service.requiresMlKitModels, isFalse);
  });

  test('apple_translate_without_id_prepares_then_translates', () async {
    expect(await translate(), '你好');
    expect(calls.map((call) => call.method), [
      'appleTranslationAvailability',
      'prepareAppleTranslation',
      'translateText',
      'cancelAppleTranslation',
    ]);
    expect(calls.first.arguments, {
      'sourceLanguage': 'en',
      'targetLanguage': 'zh',
    });
    final id = (calls[1].arguments as Map)['requestId'];
    expect(
      id,
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
    expect(calls[1].arguments, {
      'requestId': id,
      'sourceLanguage': 'en',
      'targetLanguage': 'zh',
    });
    expect(calls[2].arguments, {'requestId': id, 'text': 'Hello'});
    expect(calls[3].arguments, {'requestId': id});
  });

  test('apple_explicit_id_does_not_prepare_twice', () async {
    await service.prepare(
      requestId: 'home',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
    );
    calls.clear();
    expect(await translate(requestId: 'home'), '你好');
    expect(calls.map((call) => call.method), [
      'translateText',
      'cancelAppleTranslation',
    ]);
    expect(calls.first.arguments, {'requestId': 'home', 'text': 'Hello'});
  });

  test('apple_rejects_mismatched_response_id', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'translateText'
          ? {'requestId': 'another-request', 'translatedText': '你好'}
          : null;
    });
    await expectLater(
      translate(requestId: 'home'),
      throwsA(code('appleInvalidRequest')),
    );
    expect(calls.last.arguments, {'requestId': 'home'});
  });

  test('apple_maps_cancel_and_missing_channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'translateText') {
        throw PlatformException(code: 'appleCancelled');
      }
      return null;
    });
    await expectLater(
      translate(requestId: 'home'),
      throwsA(
        code(
          'appleCancelled',
        ).having((error) => error.isCancelled, 'isCancelled', isTrue),
      ),
    );
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      translate(requestId: 'home'),
      throwsA(code('appleTranslationFailed')),
    );
  });

  for (final status in AppleTranslationAvailability.values) {
    test('availability preserves ${status.name}', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': status.name},
      );
      expect(
        await service.availability(sourceLanguage: 'zh', targetLanguage: 'en'),
        status,
      );
    });
  }

  for (final response in <Object?>[
    null,
    'installed',
    {},
    {'status': 'unknown'},
    {'status': 1},
  ]) {
    test('availability rejects malformed response $response', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(
        service.availability(sourceLanguage: 'en', targetLanguage: 'zh'),
        throwsA(code('appleTranslationFailed')),
      );
    });
  }

  for (final response in <Object?>[
    null,
    '',
    {},
    {'requestId': 'home'},
    {'requestId': 'home', 'translatedText': ''},
    {'requestId': 'home', 'translatedText': '  '},
    {'requestId': 'home', 'translatedText': 123},
  ]) {
    test('translate rejects malformed or empty result $response', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'translateText' ? response : null,
      );
      await expectLater(
        translate(requestId: 'home'),
        throwsA(isA<AppleTranslationException>()),
      );
    });
  }

  for (final status in ['unsupported', 'platformUnsupported']) {
    test('prepare rejects $status without starting a session', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'appleTranslationAvailability'
            ? {'status': status}
            : null;
      });
      await expectLater(
        service.prepare(
          requestId: 'home',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        throwsA(
          code(
            status == 'unsupported'
                ? 'appleUnsupportedLanguage'
                : 'appleUnsupported',
          ),
        ),
      );
      expect(
        calls.where((call) => call.method == 'prepareAppleTranslation'),
        isEmpty,
      );
    });
  }

  test('cleanup failure never masks translation error or success', () async {
    for (final failTranslation in [true, false]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancelAppleTranslation') {
          throw PlatformException(code: 'cleanupFailed');
        }
        if (failTranslation) throw PlatformException(code: 'appleTimeout');
        return {'requestId': 'home', 'translatedText': '你好'};
      });
      if (failTranslation) {
        await expectLater(
          translate(requestId: 'home'),
          throwsA(code('appleTimeout')),
        );
      } else {
        expect(await translate(requestId: 'home'), '你好');
      }
    }
  });

  test(
    'prepare failure cleans only its request and preserves original error',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'appleTranslationAvailability') {
          return {'status': 'supported'};
        }
        throw PlatformException(
          code: call.method == 'prepareAppleTranslation'
              ? 'applePreparationFailed'
              : 'cleanupFailed',
        );
      });
      await expectLater(
        service.prepare(
          requestId: 'home',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        throwsA(code('applePreparationFailed')),
      );
      expect(calls.last.method, 'cancelAppleTranslation');
      expect(calls.last.arguments, {'requestId': 'home'});
    },
  );

  test('cancel is idempotent and scoped to its request', () async {
    await service.cancel('old');
    await service.cancel('old');
    expect(calls.map((call) => call.method), [
      'cancelAppleTranslation',
      'cancelAppleTranslation',
    ]);
    expect(
      calls.every((call) => (call.arguments as Map)['requestId'] == 'old'),
      isTrue,
    );
  });

  test(
    'cancel during availability prevents a late native prepare and allows retry',
    () async {
      final availability = Completer<Object?>();
      var firstCheck = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'appleTranslationAvailability') {
          if (firstCheck) {
            firstCheck = false;
            return availability.future;
          }
          return {'status': 'installed'};
        }
        return null;
      });
      final preparing = service.prepare(
        requestId: 'home',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      );
      final cancelled = expectLater(preparing, throwsA(code('appleCancelled')));
      await pumpEventQueue();
      await service.cancel('home');
      availability.complete({'status': 'supported'});
      await cancelled;
      expect(
        calls.where((call) => call.method == 'prepareAppleTranslation'),
        isEmpty,
      );
      await service.prepare(
        requestId: 'home',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      );
      expect(
        calls.where((call) => call.method == 'prepareAppleTranslation'),
        hasLength(1),
      );
    },
  );

  test('cancel another ID leaves the pending prepare usable', () async {
    final availability = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'appleTranslationAvailability') {
        return availability.future;
      }
      if (call.method == 'translateText') {
        return {'requestId': 'home', 'translatedText': '你好'};
      }
      return null;
    });
    final preparing = service.prepare(
      requestId: 'home',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
    );
    await pumpEventQueue();
    await service.cancel('screenshot');
    availability.complete({'status': 'supported'});
    await preparing;
    expect(await translate(requestId: 'home'), '你好');
  });

  test('automatic IDs are UUID v4 and unique across service lifetimes', () async {
    await translate();
    service = AppleTranslationService(channel: channel);
    await translate();
    final ids = calls
        .where((call) => call.method == 'prepareAppleTranslation')
        .map((call) => (call.arguments as Map)['requestId'])
        .toSet();
    expect(ids, hasLength(2));
    expect(
      generateAppleTranslationRequestId(),
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
  });
}
