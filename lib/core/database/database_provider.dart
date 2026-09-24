import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_store.dart';

// 应用启动时注入已打开的本地数据库。
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw StateError('LocalStore 尚未初始化'),
);
