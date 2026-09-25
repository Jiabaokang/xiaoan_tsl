# 仓库贡献指南

## 项目结构与模块组织

本仓库是小安翻译 Flutter 应用。`lib/main.dart` 初始化本地数据库与 Provider，应用页面按职责组织在 `lib/core/`、`lib/features/`、`lib/services/`；入口文件保持简洁。`test/` 包含服务、状态与组件测试。`android/`、`ios/`、`macos/` 存放平台工程，仅在需要原生配置时修改。文档入口、当前计划与历史材料见 `docs/README.md`；计划完成状态须结合当前代码和测试核对。新增应用资源时，应在 `pubspec.yaml` 中登记。

## 构建、测试与本地开发

使用与 `pubspec.yaml` 中 Dart `^3.12.2` 约束兼容的官方 Flutter SDK；仓库尚未固定 FVM 版本。官方与鸿蒙社区 SDK 的安装命令及 `fvm_ohos` 定义见 `README.md`。

- `flutter pub get`：安装并解析项目依赖。
- `flutter run`：在已连接的设备或模拟器上启动应用。
- `flutter analyze`：按 `analysis_options.yaml` 和 `flutter_lints` 进行静态检查。
- `flutter test`：运行 `test/` 下的测试。
- `flutter build appbundle --release`：配置好发布签名后生成 Android AAB。

### 设备调试与安装规则（严格执行）

- **必须在 Android 设备上调试**：涉及真机调试与运行时验证时，必须在已连接的 Android 实体设备上运行与调试，不使用其他非目标平台替代核心功能验证。
- **仅限覆盖安装，严禁卸载安装**：
  - 必须采用覆盖安装模式（例如标准的 `flutter run` 或 `adb install -r`）。
  - 绝对严禁执行卸载操作（如 `adb uninstall`、带有 `--uninstall-first` 参数的命令等）。卸载重装会触发系统级安全二次授权弹窗，导致流程中断并强依赖人工盯屏确认。覆盖安装可保持已授权状态，保证调试流畅。

## 代码风格与命名

Dart 代码使用默认的两个空格缩进，提交前运行 `dart format lib test`。文件名使用 `snake_case.dart`，类和组件使用 `UpperCamelCase`，变量与方法使用 `lowerCamelCase`。尽量拆分小组件，避免在 UI 的 `build` 方法中堆放业务逻辑。修改依赖时同步更新 `pubspec.lock`。

## 界面与中文注释规则

- 应用内图标使用 Flutter 内置的 `Icons` 或 `CupertinoIcons`，不要为界面图标引入第三方图标库。
- 应用必须支持暗色模式。新增或修改界面时使用主题中的颜色，并检查浅色、暗色两种模式下的显示效果。
- 每个类（包括私有类）定义前都要有中文说明，写清职责。核心或关键字段、方法应添加中文注释，说明用途及必要的约束；避免只重复代码表面含义。

## 测试要求

使用 `flutter_test` 编写组件测试，测试文件以 `*_test.dart` 命名。修改行为时补充或更新针对性测试；调整现有页面时同步更新对应测试。提交 PR 前运行 `flutter test` 和 `flutter analyze`。项目目前没有设置覆盖率门槛。

修改 `docs/`、`AGENTS.md` 或根目录 `README.md` 时，同批更新 `docs/CHANGELOG.md`，记录日期、内容、原因和相关文件。文档目录职责及本地提交检查的启用方式见 `docs/README.md`。

## 提交与拉取请求

提交使用简短的中文 Conventional Commit 标题，例如 `feat: 添加语言选择`、`docs: 完善开发说明`。PR 应说明改动、关联已有议题（如有）、列出验证命令及结果；可见的 UI 改动应附截图。不要提交构建产物和本地 IDE 文件。
