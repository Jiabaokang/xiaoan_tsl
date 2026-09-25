# xiaoan_tsl

集成本地模型的翻译App

## Flutter SDK（FVM）

本项目的 Dart 版本约束见 `pubspec.yaml`。开发 Android 版本时使用官方 Flutter 3.44.9；鸿蒙社区 Flutter 3.27.5-ohos-1.0.0 使用单独的仓库入口。安装前先确保已安装 FVM，并在当前 shell 中取消全局的社区镜像设置：

```sh
unset FLUTTER_GIT_URL
fvm install 3.44.9
```

`fvm_ohos` 是 shell 函数，不是 FVM 内置命令。若当前环境尚未定义，请先将以下函数加入 shell 配置并重新加载，再安装社区版本：

```sh
fvm_ohos() {
  FLUTTER_GIT_URL=https://gitcode.com/CPF-Flutter/flutter_flutter.git fvm "$@"
}
fvm_ohos install 3.27.5-ohos-1.0.0
```

如使用自定义 FVM 缓存目录，两种安装命令应使用同一个 `FVM_CACHE_PATH`。安装 SDK 不会自动为本仓库固定版本；当前仓库没有 `.fvmrc`。

### Android 打包与覆盖安装

```sh
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Release 构建需本地 `android/key.properties` 与签名证书；这些文件已忽略，不提交仓库。debug 与 Release 覆盖安装需保持相同应用 ID 和签名。真机调试必须遵守 [AGENTS.md](AGENTS.md) 的覆盖安装规则。

### 打包命令-iOS

```sh
flutter build ios --release --no-codesign
```

## 项目文档

- [文档索引](docs/README.md)：当前需求、设计、实现契约、执行计划和历史记录。
- [文档更新记录](docs/CHANGELOG.md)：逐次记录文档及协作说明的修改。

实际功能与验证进度以当前代码、测试及[活跃执行计划](docs/04_plans/current_plan.md)为准。修改文档时同步更新文档记录；本地提交检查的配置方法见[文档索引](docs/README.md#修改与验证)。
