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

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
