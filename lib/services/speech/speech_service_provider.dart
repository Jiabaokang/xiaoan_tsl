import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tts_service.dart';

// 统一提供系统朗读能力，组件测试可替换为不播放声音的实现。
final speechServiceProvider = Provider<SpeechService>(
  (ref) => FlutterTtsSpeechService(),
);
