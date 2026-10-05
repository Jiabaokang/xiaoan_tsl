import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoan_tsl/services/translation/baidu_translation_service.dart';
import 'package:xiaoan_tsl/services/translation/translation_settings.dart';

// 记录请求表单并返回可控响应的 HttpClientAdapter 替身。
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  Map<String, String>? lastForm;
  String? lastRawBody;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    lastRawBody = utf8.decode(bytes);
    lastForm = _parseForm(lastRawBody!);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}

  static Map<String, String> _parseForm(String body) {
    final form = <String, String>{};
    for (final pair in body.split('&')) {
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      form[Uri.decodeQueryComponent(pair.substring(0, index))] =
          Uri.decodeQueryComponent(pair.substring(index + 1));
    }
    return form;
  }
}

// 内存凭据替身，避免测试触碰系统 Keychain。
class _FakeCredentials implements SecureCredentialStore {
  _FakeCredentials({this.appId, this.secret});

  String? appId;
  String? secret;

  @override
  Future<String?> readBaiduAppId() async => appId;

  @override
  Future<String?> readBaiduSecret() async => secret;

  @override
  Future<bool> hasBaiduCredentials() async =>
      appId != null && appId!.isNotEmpty && secret != null && secret!.isNotEmpty;

  @override
  Future<void> writeBaiduCredentials({
    required String appId,
    required String secret,
  }) async {
    this.appId = appId;
    this.secret = secret;
  }

  @override
  Future<void> deleteBaiduCredentials() async {
    appId = null;
    secret = null;
  }
}

ResponseBody jsonBody(Map<String, Object?> json, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: const {
        'content-type': ['application/json; charset=utf-8'],
      },
    );

void main() {
  late _RecordingAdapter adapter;
  late Dio dio;
  late _FakeCredentials credentials;
  late BaiduTranslationService service;

  setUp(() {
    // 默认返回合法译文，请求类断言可正常通过解析。
    adapter = _RecordingAdapter(
      (_) async => jsonBody({
        'trans_result': [
          {'src': 'hello', 'dst': '你好'},
        ],
      }),
    );
    dio = Dio()..httpClientAdapter = adapter;
    credentials = _FakeCredentials(appId: '2015063000000001', secret: '12345678');
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
  });

  test('固定签名向量：官方示例参数生成确定 sign', () async {
    final result = await service.translate(
      text: 'apple',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
    );
    expect(adapter.calls, 1);
    final form = adapter.lastForm!;
    expect(form['appid'], '2015063000000001');
    expect(form['q'], 'apple');
    expect(form['salt'], '1435660288');
    expect(form['sign'], 'f89f9594663708c1605f3d736d01d2d4');
    expect(result, '你好');
  });

  test('UTF-8 原文先签名后表单编码，请求体为百分号编码', () async {
    const text = '你好';
    final expectedSign = md5
        .convert(utf8.encode('2015063000000001$text${1435660288}12345678'))
        .toString();
    await service.translate(
      text: text,
      sourceLanguage: 'zh',
      targetLanguage: 'en',
    );
    expect(adapter.lastRawBody, contains('%E4%BD%A0%E5%A5%BD'));
    expect(adapter.lastForm!['sign'], expectedSign);
  });

  test('当前支持语言映射到百度官方代码', () {
    expect(BaiduTranslationService.baiduLanguageCode('zh'), 'zh');
    expect(BaiduTranslationService.baiduLanguageCode('en'), 'en');
    expect(BaiduTranslationService.baiduLanguageCode('ja'), 'jp');
    expect(BaiduTranslationService.baiduLanguageCode('ko'), 'kor');
    expect(BaiduTranslationService.baiduLanguageCode('fr'), 'fra');
    expect(BaiduTranslationService.baiduLanguageCode('es'), 'spa');
    expect(BaiduTranslationService.baiduLanguageCode('de'), 'de');
    expect(BaiduTranslationService.baiduLanguageCode('pt'), 'pt');
    expect(BaiduTranslationService.baiduLanguageCode('it'), 'it');
    expect(BaiduTranslationService.baiduLanguageCode('ru'), 'ru');
    expect(BaiduTranslationService.baiduLanguageCode('xx'), isNull);
  });

  test('日文请求使用 jp 代码发出', () async {
    await service.translate(
      text: 'こんにちは',
      sourceLanguage: 'ja',
      targetLanguage: 'zh',
    );
    expect(adapter.lastForm!['from'], 'jp');
    expect(adapter.lastForm!['to'], 'zh');
  });

  test('未知语言代码在发请求前拒绝', () async {
    await expectLater(
      service.translate(
        text: 'hello',
        sourceLanguage: 'xx',
        targetLanguage: 'zh',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(adapter.calls, 0);
  });

  test('多个 trans_result 按接口顺序拼接并保留段落', () async {
    adapter = _RecordingAdapter(
      (_) async => jsonBody({
        'trans_result': [
          {'src': 'a', 'dst': '甲'},
          {'src': 'b', 'dst': '乙'},
        ],
      }),
    );
    dio = Dio()..httpClientAdapter = adapter;
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
    final result = await service.translate(
      text: 'a\nb',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
    );
    expect(result, '甲\n乙');
  });

  test('空 trans_result 视为协议错误而不是成功', () async {
    adapter = _RecordingAdapter(
      (_) async => jsonBody({'trans_result': <Object>[]}),
    );
    dio = Dio()..httpClientAdapter = adapter;
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
    await expectLater(
      service.translate(
        text: 'hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      ),
      throwsA(isA<BaiduProtocolException>()),
    );
  });

  test('缺少 dst 字段的译文块视为协议错误', () async {
    adapter = _RecordingAdapter(
      (_) async => jsonBody({
        'trans_result': [
          {'src': 'a'},
        ],
      }),
    );
    dio = Dio()..httpClientAdapter = adapter;
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
    await expectLater(
      service.translate(
        text: 'hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      ),
      throwsA(isA<BaiduProtocolException>()),
    );
  });

  test('HTTP 200 带 error_code 仍按业务错误分类抛出', () async {
    final cases = <String, Type>{
      '52003': BaiduAuthException,
      '54001': BaiduAuthException,
      '90107': BaiduAuthException,
      '54003': BaiduRateLimitException,
      '54005': BaiduRateLimitException,
      '54004': BaiduQuotaException,
    };
    for (final entry in cases.entries) {
      adapter = _RecordingAdapter(
        (_) async => jsonBody({
          'error_code': entry.key,
          'error_msg': '测试错误',
        }),
      );
      dio = Dio()..httpClientAdapter = adapter;
      service = BaiduTranslationService(
        credentials: credentials,
        dio: dio,
        saltFactory: () => 1435660288,
      );
      await expectLater(
        service.translate(
          text: 'hello',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        throwsA(isA<BaiduTranslationException>().having(
          (e) => e.runtimeType,
          'type',
          entry.value,
        )),
      );
    }
  });

  test('错误消息不包含密钥或完整原文', () async {
    adapter = _RecordingAdapter(
      (_) async => jsonBody({'error_code': '54001', 'error_msg': '签名错误'}),
    );
    dio = Dio()..httpClientAdapter = adapter;
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
    try {
      await service.translate(
        text: '极长的一段完整原文内容用于验证不泄露',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      );
      fail('应当抛出业务错误');
    } on BaiduTranslationException catch (error) {
      expect(error.message, isNot(contains('12345678')));
      expect(error.message, isNot(contains('2015063000000001')));
      expect(error.message, isNot(contains('极长的一段完整原文')));
    }
  });

  test('缺凭据时返回配置错误且不发请求', () async {
    credentials = _FakeCredentials();
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
    await expectLater(
      service.translate(
        text: 'hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      ),
      throwsA(isA<BaiduConfigException>()),
    );
    expect(adapter.calls, 0);
  });

  test('非 JSON 响应按协议错误处理', () async {
    adapter = _RecordingAdapter(
      (_) async => ResponseBody.fromString(
        'not json at all',
        200,
        headers: const {
          'content-type': ['application/json; charset=utf-8'],
        },
      ),
    );
    dio = Dio()..httpClientAdapter = adapter;
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
    await expectLater(
      service.translate(
        text: 'hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      ),
      throwsA(isA<BaiduProtocolException>()),
    );
  });

  test('网络超时按网络错误分类', () async {
    adapter = _RecordingAdapter((options) async {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    });
    dio = Dio()..httpClientAdapter = adapter;
    service = BaiduTranslationService(
      credentials: credentials,
      dio: dio,
      saltFactory: () => 1435660288,
    );
    await expectLater(
      service.translate(
        text: 'hello',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
      ),
      throwsA(isA<BaiduNetworkException>()),
    );
  });
}
