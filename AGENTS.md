# 仓库贡献指南

## 项目结构与模块组织

本仓库是 Flutter 应用。`lib/main.dart` 目前仍是计数器示例；新增 Dart 功能放在 `lib/` 下，并保持入口文件简洁。`test/widget_test.dart` 是现有的组件冒烟测试。`android/`、`ios/`、`macos/` 存放平台工程，仅在需要原生配置时修改。`docs/` 中的中文翻译应用文档是功能规划，不代表功能已经实现。目前 `pubspec.yaml` 未声明应用资源；新增图片等资源时，应创建相应目录并在该文件中登记。

## 构建、测试与本地开发

使用与 `pubspec.yaml` 中 Dart `^3.12.2` 约束兼容的官方 Flutter SDK；仓库尚未固定 FVM 版本。官方与鸿蒙社区 SDK 的安装命令及 `fvm_ohos` 定义见 `README.md`。

- `flutter pub get`：安装并解析项目依赖。
- `flutter run`：在已连接的设备或模拟器上启动应用。
- `flutter analyze`：按 `analysis_options.yaml` 和 `flutter_lints` 进行静态检查。
- `flutter test`：运行 `test/` 下的测试。
- `flutter build appbundle --release`：配置好发布签名后生成 Android AAB。

## 代码风格与命名

Dart 代码使用默认的两个空格缩进，提交前运行 `dart format lib test`。文件名使用 `snake_case.dart`，类和组件使用 `UpperCamelCase`，变量与方法使用 `lowerCamelCase`。尽量拆分小组件，避免在 UI 的 `build` 方法中堆放业务逻辑。修改依赖时同步更新 `pubspec.lock`。

## 界面与中文注释规则

- 应用内图标使用 Flutter 内置的 `Icons` 或 `CupertinoIcons`，不要为界面图标引入第三方图标库。
- 应用必须支持暗色模式。新增或修改界面时使用主题中的颜色，并检查浅色、暗色两种模式下的显示效果。
- 每个类（包括私有类）定义前都要有中文说明，写清职责。核心或关键字段、方法应添加中文注释，说明用途及必要的约束；避免只重复代码表面含义。

## 测试要求

使用 `flutter_test` 编写组件测试，测试文件以 `*_test.dart` 命名。修改行为时补充或更新针对性测试；替换计数器示例页面时，也要更新对应的现有测试。提交 PR 前运行 `flutter test` 和 `flutter analyze`。项目目前没有设置覆盖率门槛。

## 提交与拉取请求

`main` 分支尚无提交，因此没有可沿用的历史提交格式。建议使用简短的祈使式标题，例如 `feat: 添加语言选择`、`docs: 完善开发说明`。PR 应说明改动、关联已有议题（如有）、列出验证命令及结果；可见的 UI 改动应附截图。不要提交构建产物和本地 IDE 文件。
