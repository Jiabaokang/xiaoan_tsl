import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'translation_service.dart';
import 'translation_settings.dart';

// 百度服务错误分类；任何消息都不包含密钥或完整原文。
sealed class BaiduTranslationException implements Exception {
  const BaiduTranslationException(this.message);

  final String message;

  @override
  String toString() => message;
}

// 缺少或未填写 AppID/密钥，属于配置错误而不是请求失败。
class BaiduConfigException extends BaiduTranslationException {
  const BaiduConfigException(super.message);
}

// 认证失败：签名错误、未授权账号、客户端 IP 非法、认证未生效等。
class BaiduAuthException extends BaiduTranslationException {
  const BaiduAuthException(super.message);
}

// 访问频率受限，首版不做自动重试，由用户手动重试。
class BaiduRateLimitException extends BaiduTranslationException {
  const BaiduRateLimitException(super.message);
}

// 账户余额或额度不足。
class BaiduQuotaException extends BaiduTranslationException {
  const BaiduQuotaException(super.message);
}

// 网络超时、连接失败等传输层错误。
class BaiduNetworkException extends BaiduTranslationException {
  const BaiduNetworkException(super.message);
}

// 响应结构不符合契约或业务返回错误，不代表翻译成功。
class BaiduProtocolException extends BaiduTranslationException {
  const BaiduProtocolException(super.message);
}

// 百度翻译开放平台通用文本翻译；只接受 AppID＋密钥分支。
class BaiduTranslationService implements TranslationService {
  BaiduTranslationService({
    required this.credentials,
    required this.dio,
    this.saltFactory,
  });

  static const endpoint = 'https://fanyi-api.baidu.com/api/trans/vip/translate';

  // 当前应用语言代码到百度官方语言代码的映射。
  static const _languageCodes = <String, String>{
    'zh': 'zh',
    'en': 'en',
    'ja': 'jp',
    'ko': 'kor',
    'fr': 'fra',
    'de': 'de',
    'es': 'spa',
    'pt': 'pt',
    'it': 'it',
    'ru': 'ru',
  };

  // 测试注入固定 salt 以获得确定性签名；生产使用随机值。
  static final _random = Random.secure();

  final SecureCredentialStore credentials;
  final Dio dio;
  final int Function()? saltFactory;

  @override
  String get engineId => 'baidu';

  @override
  bool get requiresMlKitModels => false;

  // 应用内部语言代码是否可在发请求前映射到百度官方代码。
  static bool supportsLanguage(String code) => _languageCodes.containsKey(code);

  // 按官方支持列表映射；未知代码返回 null，由调用方在发请求前拒绝。
  static String? baiduLanguageCode(String code) => _languageCodes[code];

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final appId = await credentials.readBaiduAppId();
    final secret = await credentials.readBaiduSecret();
    if (appId == null || appId.isEmpty || secret == null || secret.isEmpty) {
      throw const BaiduConfigException('缺少百度翻译凭据，请先在设置中填写');
    }
    final from = baiduLanguageCode(sourceLanguage);
    final to = baiduLanguageCode(targetLanguage);
    if (from == null || to == null) {
      throw ArgumentError.value(
        from == null ? sourceLanguage : targetLanguage,
        'language',
        '百度暂不支持该语言代码',
      );
    }
    final salt = (saltFactory?.call() ?? _random.nextInt(1 << 32)).toString();
    // 先对未编码原文签名，再由 Dio 做表单编码。
    final sign = md5.convert(utf8.encode('$appId$text$salt$secret')).toString();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        endpoint,
        data: <String, String>{
          'q': text,
          'from': from,
          'to': to,
          'appid': appId,
          'salt': salt,
          'sign': sign,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = response.data;
      if (body == null) {
        throw const BaiduProtocolException('百度返回了空响应');
      }
      final errorCode = body['error_code'];
      if (errorCode != null) {
        _throwByErrorCode(errorCode.toString(), body['error_msg']?.toString());
      }
      // HTTP 200 不代表翻译成功；必须有按原顺序排列的译文块。
      final results = body['trans_result'];
      if (results is! List || results.isEmpty) {
        throw const BaiduProtocolException('百度未返回译文结果');
      }
      final buffer = StringBuffer();
      for (final item in results) {
        if (item is! Map) {
          throw const BaiduProtocolException('百度译文结果结构错误');
        }
        final dst = item['dst'];
        if (dst == null) {
          throw const BaiduProtocolException('百度译文缺少 dst 字段');
        }
        buffer.writeln(dst);
      }
      // 多段结果保持接口返回顺序，用换行分隔。
      return buffer.toString().trimRight();
    } on DioException catch (error) {
      throw _networkError(error);
    }
  }

  // 按官方错误码分类；消息只带错误码，不包含密钥与原文。
  BaiduTranslationException _throwByErrorCode(String code, String? message) {
    final detail = message == null || message.isEmpty ? '错误码 $code' : message;
    final exception = switch (code) {
      '52003' ||
      '54001' ||
      '58000' ||
      '90107' => BaiduAuthException('百度认证失败：$detail'),
      '54003' || '54005' => BaiduRateLimitException('百度请求过于频繁：$detail'),
      '54004' => BaiduQuotaException('百度账户额度不足：$detail'),
      '52001' => BaiduNetworkException('百度请求超时：$detail'),
      _ => BaiduProtocolException('百度返回错误：$detail'),
    };
    throw exception;
  }

  BaiduNetworkException _networkError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const BaiduNetworkException('百度请求超时，请检查网络后重试');
    }
    if (error.type == DioExceptionType.connectionError) {
      return const BaiduNetworkException('无法连接百度服务，请检查网络');
    }
    if (error.type == DioExceptionType.unknown &&
        error.error is FormatException) {
      throw const BaiduProtocolException('百度返回了无法解析的响应');
    }
    return const BaiduNetworkException('百度网络请求失败，请稍后重试');
  }
}
