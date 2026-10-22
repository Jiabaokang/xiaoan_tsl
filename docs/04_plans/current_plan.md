# 小安翻译 v1.0 活跃执行计划 (Current Execution Plan)

> **当前阶段**：v1.0 冲刺收官与 Google Play 准入就绪阶段  
> **当前验证**：macOS 苹果离线翻译代码已接入并通过自动化回归；2026-10-20 全量 Flutter 测试 275 项、RunnerTests 40 项（1 项实机语言包测试跳过）通过，`flutter analyze` 无问题。真实语言包下载、断网翻译、macOS 14 与完整实机矩阵仍待验收。
> **执行依据**：严格遵循 `docs/01_prd/prd_v1.0.md` 与 `docs/03_specs/` 各专项规格。
> **历史步骤**：[核心框架实施计划](../superpowers/plans/2026-09-24-core-framework.md)与[v1 剩余功能实施计划](../superpowers/plans/2026-09-24-v1-completion.md)保留编写时的任务快照；本文件记录当前进度。

---

## 任务拆解与进度检查清单

### 开发完成、实机验收待完成：macOS 苹果离线翻译（2026-10-20）

- [x] 按[接入开发文档](../superpowers/plans/20261020151615_macOS苹果离线翻译接入开发文档.md)实现 macOS 15+ 系统语言包准备、首页与截图翻译、取消/超时及错误恢复。
- [x] 新增 `AppleTranslationBridge.swift`、`apple_translation_service.dart`，接入既有桌面通道、设置页能力查询、首页与截图两阶段准备、独立 requestId、取消清理和错误本地化；默认百度与百度凭据保持不变。
- [x] 验证：`flutter test` 275 项通过，`flutter analyze` 无问题，macOS Debug 构建成功；RunnerTests 执行 40 项、1 项跳过、0 失败；Android OnePlus 9 已覆盖安装并完成启动回归，无崩溃。
- [x] 证据边界：本机 macOS 26.7.1（x86_64）报告 en→zh-Hans 为 `supported`，语言包尚未安装，因此真实准备与翻译会话测试跳过；未执行真实断网、系统下载授权、系统 sheet、全屏 Space 或真实截图闭环。
- [ ] 完成系统 14 兼容、真实模型准备与取消重试、断网翻译及移动端回归，登记本轮证据。
- 当前 apple 选项在 macOS 15+ 由真实能力查询开放，`supported` 和 `installed` 均可选择；其他平台仍禁用。苹果失败不会自动回退百度或上传原文。开发状态不等于实机验收完成。

### 阶段一：朗读能力接线与生命周期测试（V1-05）
- [x] 1.1 `TtsService` 基础实现与单测（已通过 `test/services/speech/tts_service_test.dart`）
- [x] 1.2 首页原文与译文朗读按钮接入与状态控制
  - **目标文件**：`lib/features/translate/translation_home_page.dart`
  - **验收结果**：原文与译文已配置独立朗读按钮、`_speaking` 状态控制，支持主动停止，退出时释放资源。`test/widget_test.dart` 朗读用例与异常提示全量通过。

### 阶段二：离线模型管理完善（V1-04）
- [x] 2.1 离线模型列表查询、手动下载与删除实现（已通过基础单测）
- [x] 2.2 完善模型删除保护与蜂窝网络下载确认
  - **目标文件**：`lib/features/language/offline_models_page.dart`
  - **验收结果**：翻译进行中（`state.phase.isBusy`）禁用模型删除；管理页下载失败后可确认使用移动流量重试。首页缺模型时先确认，再允许本次下载使用移动网络并自动续译；OnePlus 6 已在 Wi-Fi 下完成真实模型下载与英中翻译。

### 阶段三：应用合规、关于与隐私信息真实化（V1-07）
- [x] 3.1 动态读取真实版本与构建号
  - **目标文件**：`lib/features/settings/info_page.dart`
  - **验收结果**：成功接入 `package_info_plus`，实体机实测动态显示 `版本 1.0.0 (1)`。
- [x] 3.2 隐私政策文案与合规声明
  - **目标文件**：`lib/features/settings/info_page.dart`、`docs/01_prd/compliance/privacy_policy.md`
  - **验收结果**：应用内声明离线翻译特性、零服务器上传、关闭系统备份，通过 Widget 测试与实体机浏览。

### 阶段四：Android Release 签名与 AAB 构建（V1-08）
- [x] 4.1 分离 Release 签名配置
  - **目标文件**：`android/app/build.gradle.kts`、`android/app/proguard-rules.pro`
  - **验收结果**：`key.properties` 与签名证书保留在本地并被 Git 忽略；Release 保留 ML Kit 反射创建所需的组件注册器构造函数。
- [x] 4.2 执行 Release AAB 构建
  - **验收结果**：成功构建生产级安装包 `build/app/outputs/bundle/release/app-release.aab`（93.9MB），无 ProGuard/R8 符号丢失错误。

### 阶段五：Android 实体设备验收与 Play 轨道发布（V1-09）
- [x] 5.1 真机覆盖安装验证（严格遵守 `AGENTS.md`，仅覆盖安装）
  - **已连接设备**：`M2002J9E (android-arm64, Android 12, API 31, ID: d5bf1745)`
  - **执行命令**：`adb -s d5bf1745 install -r build/app/outputs/flutter-apk/app-debug.apk`
  - **验证成果（附截图证据）**：
    1. 首页正常启动无崩溃；
    2. 点击示例 "Hello, world!" 自动识别 English 并成功在端侧离线翻译为 "你好，世界！"；
    3. 翻译结果自动写入本地 SQLite 历史，支持去重防抖；
    4. “我的收藏”列表正常过滤已收藏条目；
    5. “离线语言包”页面通过 ML Kit Model Manager 成功读取中/英已下载状态；
    6. “关于”页面动态显示应用版本；
    7. 目标语言选择器屏蔽“自动检测”项，仅允许选择明确语种。
- [ ] 5.2 Google Play Closed Testing 测试配置（需开发者账号拥有者配合）
  - **待办**：在 Play Console 配置 Closed Testing 轨道，邀请 12 名测试人员开始 14 天测试流程。

### 阶段六：国际化多语言支持（V1-10）
- [x] 6.1 中英文多语言架构与基类实现
  - **目标文件**：`lib/l10n/app_localizations.dart`、`pubspec.yaml`
  - **验收结果**：接入 `flutter_localizations` 与 `intl`，定义双语契约与 `context.l10n` 语法糖，映射语言展示名称。
- [x] 6.2 语言模式状态持久化与系统跟随
  - **目标文件**：`lib/features/translate/app_controller.dart`、`lib/app.dart`
  - **验收结果**：支持 `system` / `zh` / `en`，通过本地存储持久化；应用入口支持 `localeListResolutionCallback` 自适应解析。
- [x] 6.3 全量页面硬编码抽取与设置页切换交互
  - **目标文件**：首页、设置、历史与收藏、语言选择、离线模型、关于等页面
  - **验收结果**：所有界面文字抽离至 Localizations，设置页增加语言切换弹窗，即时切换。
- [x] 6.4 自动化测试补充与真机验证
  - **目标文件**：`test/widget_test.dart`
  - **验收结果**：新增系统语言跟随与手动切换、持久化恢复及返回导航兼容测试，全量 42 项自动化测试 100% 通过。

### 2026-09-25 真机问题修复

- [x] OnePlus 9（Android 14）上短文本 `Hello` 曾被五字符识别门槛拦截；已选原文语言时识别不确定会使用所选语言。修复后的 debug 与 Release 均自动译出“你好”。
- [x] Release 离线语言包曾因 R8 移除 ML Kit 组件注册器构造函数而无法查询；加入保留规则后，覆盖安装的 Release 能显示语言选择列表及离线模型状态。
- [x] 全量 `flutter test` 39 项通过，`flutter analyze` 无问题；两次安装均使用 `adb install -r`，未卸载或清除应用数据。

---

## macOS 截图翻译实施进度（2026-10-02 起）

**计划链接**：[macOS 截图翻译实施计划](../superpowers/plans/20261002225612_macOS截图翻译实施计划.md)（逐项勾选以此为准）。

**执行约定**：用户在 dev 分支要求完成开发工作，不提交代码；每完成一步在计划文档打勾。

### Task 0：核对目标、环境和当前基线（完成）
- 工作树：存在未提交的平板文档（`docs/02_design/tablet_adaptation_guide.md`）与 `docs/README.md`、`docs/CHANGELOG.md` 改动，未纳入本次范围。
- 环境：Flutter 3.44.9 stable / Dart ^3.12.2；macOS 26.7.1（x86_64）；Xcode 26.4；`flutter devices` 无 Android 实体设备连接。
- 基线：`flutter analyze` 0 问题；全量 `flutter test` 101 项通过（2026-10-03 记录）。
- 百度账号类型未与用户确认：按计划默认开放平台 AppID/密钥分支实施；智能云分支未启用（Task 2 对应复选框未勾选）。

### Task 1：让翻译流程按实际服务运行（完成）
- `TranslationService.requiresMlKitModels`；ML Kit 返回 true，在线服务 false。
- 请求开始固定服务；模型检查/下载只属于 ML Kit；在线服务不读取模型 Provider。
- Provider 同文件提供 `translationPlatformProvider` 可覆盖平台选择；macOS 不创建 ML Kit；未知/未交付配置回退平台默认；缺凭据返回 `BaiduConfigException` 配置错误。
- `AppController.setTranslationEngine` 切换服务并让旧请求失效（首页规则已建立）。
- 变更文件：`translation_service.dart`、`mlkit_translation_service.dart`、`translation_service_provider.dart`、`app_controller.dart`、`app_localizations.dart`、`translation_home_page.dart`。
- 测试：`translation_service_provider_test.dart`、`real_translation_flow_test.dart`、`app_controller_test.dart` 及全部 `implements TranslationService` 替身更新，通过。

### Task 2：接入用户实际持有的百度服务（完成，智能云分支除外）
- 新增 `baidu_translation_service.dart`、`translation_settings.dart`；`pubspec` 声明 `crypto`、`flutter_secure_storage`（锁文件已解析）。
- 固定签名向量 `f89f9594663708c1605f3d736d01d2d4`、UTF-8 先签名后编码、语言映射（ja/jp、ko/kor、fr/fra、es/spa）、分段 dst 顺序、业务/网络/协议错误分类、错误不含密钥与原文；不自动重试。
- 测试：`baidu_translation_service_test.dart`、`translation_settings_test.dart` 通过；数据库设置不包含 secret。

### Task 3：提供安全可理解的服务设置（完成）
- 新增 `/translation-service`（`translation_service_page.dart`）：平台服务列表、apple 禁用、凭据掩码保存/删除、固定短句测试连接（前置说明、失败保留输入）、在线数据传输说明、macOS 截图快捷键设置项（原生注册留待 Task 5）。
- 设置页增加“翻译服务”入口；macOS 隐藏离线语言包入口且 `/offline-models` 直接访问不读模型 Provider；历史与首页引擎标签统一本地化；配置错误在首页显示“前往配置”入口。
- 测试：`translation_service_page_test.dart` 9 项与 `widget_test.dart` 更新后全量通过。

### Task 4：macOS 截图/OCR/语言识别原生桥（实现完成，实机验收在 Task 7）
- Dart 侧 `macos_desktop_service.dart`：通道方法 captureRegion/recognizeText/identifyLanguage/showResultWindow/cancelCapture；错误码 permissionDenied/captureFailed/ocrFailed/shortcutConflict/platformUnsupported 映射为领域异常；非 macOS 返回不支持实现并抛明确异常；Provider 按平台选择。
- 原生侧：`ScreenCaptureCoordinator.swift`（CGPreflight/CGRequest 权限、SCShareableContent+SCScreenshotManager 全屏快照、cropPixelRect 纯函数、Vision OCR 阅读顺序排序、Natural Language 语言映射）、`MacDesktopBridge.swift`（通道 handler、SelectionOverlayView 框选覆盖层、Esc/极小区域取消、跨屏按显示器边界裁切、完成回调恰好一次）；`MainFlutterWindow.swift` 注册 bridge。
- 工程配置：pbxproj 注册两个 Swift 文件并补 DEFINES_MODULE/PRODUCT_MODULE_NAME；最低 macOS 14（Podfile + 3 个构建配置）；Debug/Release entitlements 增加 network.client；Info.plist 版本键沿用部署目标变量无需改动；main.dart 启动路径已核实无移动端专属流程。
- 验证：`flutter analyze` 0 问题；桌面通道 Dart 测试 11 项通过；`flutter build macos --debug` 成功；RunnerTests 原生单测 6 项通过（Retina 倍率、负坐标、Y 翻转、屏幕边缘、极小/越界选区）。
- 未完成：Task 4 完成条件的实际 Mac 截图与 OCR 运行验收、ML Kit MissingPluginException 消除确认，留待 Task 7 实机验收；Task 5 的快捷键注册未接。

**当前状态**：Task 5 进行中（菜单栏常驻、全局快捷键、单窗口）。

### Task 5：菜单栏常驻、全局快捷键与单窗口（实现完成，运行场景验收在 Task 7）
- 原生：Carbon RegisterEventHotKey 只注册用户指定组合（默认 Control+Option+T），先注册新键成功再注销旧键，冲突返回 shortcutConflict 且保留旧注册；快捷键/菜单动作经 EventChannel 仅通知 Dart；AppDelegate 最后窗口关闭不退出、关闭时隐藏窗口保留引擎、applicationWillTerminate 注销快捷键与通道；MainFlutterWindow.showResultWindow/restoreMainWindow 保存正常 frame/style 并在屏幕内计算结果窗位置。
- Dart：`MacosDesktopService.updateShortcut` + `events` 事件流（screenshotHotkey/openSettings）；main.dart macOS 启动恢复已保存快捷键配置；设置页新增快捷键选择对话框（注册成功才保存，冲突保留原设置）；l10n 中英文键补齐。
- 验证：`flutter analyze` 0 问题；桌面通道测试 15 项通过；RunnerTests 原生单测 9 项通过（含快捷键解析）；`flutter build macos --debug` 成功；全量 `flutter test` 116 项通过。
- 未完成：全屏 Spaces 辅助窗口行为、后台/关窗/重复切换快捷键/注销重启场景的实机验证，归入 Task 7。

### Task 6：截图结果连接翻译服务（实现完成）
- 新增 `lib/features/screenshot/screenshot_controller.dart`：会话序号与请求开始固定服务；`ref.listen(translationEngineProvider)` 服务切换即失效回 idle；startCapture 先取消旧会话再捕获（重复触发安全）；OCR 空/超 5000 字符/权限/捕获失败/不支持分别映射 noText/tooLong/permissionDenied/captureFailed/unsupported；非英文或低置信度先进 needsConfirm，用户确认后才发请求；固定 en→zh、30 秒超时（可注入）；成功会话保存 TranslationRecord 并刷新 AppController 历史。
- 新增 `lib/features/screenshot/screenshot_result_page.dart`：截图在上、原文/中文译文在下，长内容 ListView 滚动；done 提供复制/重新截图，failed 按失败类型提供前往配置/重试/重新截图；Esc 与关闭按钮 dismiss 释放截图内存；服务切换回 idle 自动关闭页面；浅/暗色与中英文文案齐备。
- 挂接：`app_router.dart` 增加 `/screenshot-result`；`app.dart` 重写为 DesktopEventBridge（订阅桌面事件流：screenshotHotkey→startCapture+进入结果页、openSettings→设置页），不等待 API 完成即展示截图；`app_controller.dart` 增加 `refreshRecords()`。
- 测试：控制器测试 13 项（捕获取消/权限/空识别/超长/非英文确认/英文直译/缺凭据计数为零/超时/旧响应丢弃/服务切换失效/历史保存失败/关闭释放/重试复用原文）+ 结果页测试 10 项（中英、明暗、长文本滚动、按钮与失败文案、确认后完成、关闭释放），全量 `flutter test` 139 项通过，`flutter analyze` 0 问题。
- 未完成：实际 Mac 上从快捷键到译文完整闭环（Task 6 完成条件），归入 Task 7 实机验收。

**当前状态**：Task 6 实现完成并登记；Task 7（首版回归与交付记录）待开始。

---

## 2026-10-05：macOS 已授权仍拒绝截图的排查与修复

- 系统日志确认两个独立原因：14:30 的截图请求被归属到 `com.microsoft.VSCode`，返回 `authValue=0`；独立启动后 ScreenCaptureKit 仍拒绝，14:46 的 TCC 日志明确报告 `Failed to match existing code requirement`。旧授权绑定 `421bebaf…`，新应用临时签名为 `856031e3…`，设置开关开启不代表新版签名已获授权。
- 原生捕获改为由 ScreenCaptureKit 实际结果判断授权，移除 CGPreflight/CGRequest 的提前拦截及“申请成功仍报拒绝”分支。只有 `SCStreamError.userDeclined` 映射为权限错误，其他捕获错误保留原生域和错误码用于诊断；中英文提示说明已授权时完全退出后独立启动，以及 IDE 自身权限的影响。
- `AppInfo.xcconfig` 可选加载本机 `LocalSigning.xcconfig`，该文件由 `macos/.gitignore` 排除。本机已使用现有 Apple Development 证书配置稳定开发签名；其他开发者应填写自己的 `CODE_SIGN_IDENTITY` 与 `DEVELOPMENT_TEAM`。缺少本机配置时保持原构建设置。
- 验证：新增权限提示回归测试先复现旧提示缺少已授权处理说明；完整 Flutter 测试 144 项通过，原生 RunnerTests 11 项通过，`flutter analyze` 无问题，`git diff --check` 通过。原生测试覆盖真实拒绝码、其他 ScreenCaptureKit 错误及其他域同码错误。
- `flutter build macos --debug` 成功；`codesign -d -r-` 确认 designated requirement 已采用应用标识、Apple 证书与证书身份，而非每次构建变化的 cdhash。个人证书与团队只保存在本机忽略文件中。
- 实际 Mac 捕获已执行，确认故障发生在系统捕获授权阶段，尚未进入 OCR 或翻译 API。修复版已准备好，已请求用户关闭后重新开启 `xiaoan_tsl` 录屏开关以重新关联旧授权；完成后继续验证真实截图、OCR 和译文。此处不把自动化测试作为完整实机验收。

## 2026-10-05：设置主页全局截图快捷键与后台框选

- 将已有快捷键入口从“翻译服务”移到设置主页，支持四个组合与关闭选项；默认 `Control+Option+T`。注册成功后保存至本机数据库，冲突保留旧配置；保存失败时尝试恢复原注册，并显示失败提示。中英文说明补充最小化/后台可用、拖拽框选、松开识别与翻译以及 Esc 取消。
- 原生诊断实际确认无边框 `NSPanel.canBecomeKey=false`，选区视图默认 `acceptsFirstMouse=false`。新增可成为键盘焦点的选区面板，接受首次点击，设置十字光标与框选提示；显示面板前安装完成回调，取消预取中的旧请求，避免重复触发遗留窗口。
- 截图前隐藏应用自己的进度窗口；选区完成后恢复最小化窗口并显示结果。屏幕面板使用 `NSScreen` 的 Cocoa 坐标，裁剪使用选区局部坐标，结果窗口使用全局坐标。
- Apple SDK 头文件明确 `SCDisplay.width/height` 单位为 point，原实现误当像素。快照尺寸现按屏幕 Retina 倍率生成，与选区裁剪保持一致。
- OCR 已存在并由真实 Vision 调用验证：自建英文 PNG 成功识别 `Hello world`。完整 Flutter 回归 145 项、原生回归 14 项通过，`flutter analyze` 无问题；最终 macOS 应用构建与开发证书签名核验通过，Dart 格式与差异检查通过。
- 真实屏幕快照验收仍被系统拒绝，错误为 `com.apple.ScreenCaptureKit.SCStreamErrorDomain/-3801`。15:26 的 TCC 日志再次确认旧授权仍绑定 `421bebaf…`，尚未匹配当前稳定开发证书签名。因此 OCR 本身已验证，实际屏幕快照→OCR→百度译文的完整验收仍须先重新关联系统授权，不能报告为已通过。

## 2026-10-05：清理失效录屏授权并恢复正式系统申请

- 用户反馈应用与 VS Code 的系统开关均已开启，但仍循环进入权限错误页。15:32 的 TCC 日志确认录屏记录仍绑定旧 `421bebaf…` 临时签名，不匹配现有 Apple Development 证书。
- 正常结束本工作区应用后，执行仅针对本应用的 `tccutil reset ScreenCapture com.example.xiaoanTsl`，系统返回 `Successfully reset`；重新启动后的捕获请求已不再报告旧签名要求不匹配。未卸载应用或清理翻译数据。
- 重置后还确认 `replayd` 日志为 `Service kTCCServiceScreenCapture does not allow prompting; returning denied`。移除预检拦截时一并移除了正式申请，导致捕获服务无法代表应用发起首次授权。现于原生截图入口补回 `CGRequestScreenCaptureAccess()`，不以其返回值提前拒绝捕获，最终结果仍由 ScreenCaptureKit 判断。
- 新修复版构建成功，原生回归 14 项通过，差异检查通过。已准备由当前签名重新触发系统授权；实际屏幕捕获与翻译的最终验收仍需用户完成新的系统确认。

## 2026-10-20：macOS 截图翻译改造为原位覆盖面板

- **交互演进**：响应“选区后直接在截图区域上显示对应翻译内容、覆盖在原内容上方”的需求，将原先侧边弹出的独立结果窗口改造为原位覆盖面板（`OverlayResultPanel` + `OverlayResultView`）。
- **架构轻量化**：完全移除原先用于渲染结果窗口的第二个 Flutter Engine（`screenshot_result` / `screenshotWindowMain` 废弃保留空实现兼容），改用纯原生 AppKit 组件渲染，消除多引擎内存开销与跨引擎启动延迟。
- **原位覆盖特性**：
  - 选区框选保持全屏快照与自由拖拽高亮边框；松开鼠标后关闭全屏遮罩，仅在截图选区精确坐标生成无边框浮动面板。
  - OCR 与翻译阶段在选区原位展示加载指示器与进度文案。
  - 翻译完成后译文自适应字号填充（下限 11pt），超长文本支持向下自适应扩展（最高 2 倍选区高度）。
  - 面板底部配备微型浮动工具条：支持一键复制（带 ✓ 反馈）、按住/点击查看原文 Peek 模式、重新截图、关闭。
  - 支持 Esc 键、点击面板外任意区域、或 3 分钟无操作自动淡出关闭。
  - 浅色/暗色模式自适应（高对比度毛玻璃/半透明纯色背景与文本色）。
- **通道协议收敛**：Dart 侧 `app.dart` 中的 `_publishResult` 仅发送业务状态快照，无需推送 Flutter 主题与语言模式（由原生外观代理处理）。
- **验证结果**：
  - `flutter analyze lib/ test/`：0 错误、0 警告；
  - `flutter test`：全量 172 项单元、状态机与组件测试 100% 通过；
  - `flutter build macos --debug`：Xcode 原生工程与 Swift 代码编译构建通过。

## 2026-10-12：截图结果独立窗口与 Dock 唤起

- 结果页不再覆盖 macOS 主窗口的导航或尺寸；Dock 和菜单入口打开主页，截图结果仍可独立查看。系统红色关闭、页面关闭、Esc 结束截图会话并恢复主页；关主页只隐藏，明确退出才结束应用。
- 使用公开 API 创建按需复用的结果展示引擎，复用现有结果页。结果引擎不打开数据库或凭据、不注册快捷键、不直接调用翻译服务；通过快照同步语言和主题、通过主引擎处理操作。Android/iOS 保留原启动和翻译流程，未改动平台工程及服务逻辑。
- 原生窗口回归 15 项通过，覆盖主窗口尺寸与最小化状态、Dock 在结果可见时唤起、两个窗口的关闭、截图前隐藏和结果窗口复用。新增结果窗口组件测试覆盖浅色、暗色、英文配置入口与操作转发，新增主页输入保留测试。
- 最终验证：`flutter test --no-pub` 165 项通过，`flutter analyze --no-pub` 无问题，原生 RunnerTests 15 项通过，`git diff --check` 通过。`scripts/install_macos.sh` 构建 Release 成功并覆盖安装、启动 `~/Applications/xiaoan_tsl.app`；固定路径进程与 `codesign --verify --deep --strict` 签名验证通过。未提交或推送代码。
- 当前没有连接 Android 实体设备。全屏 Spaces、多显示器及真实截图到译文的完整交互验收尚未执行，不以窗口测试代替。

## 质量验证红线（Hard Gates）

当前工程已通过以下验证：
1. `dart format lib test`：代码格式规范；
2. `flutter analyze`：**0 warning, 0 error**；
3. `flutter test`：**全量 42 项单元/组件/状态机测试通过**；
4. `flutter build apk --debug`：构建成功，并在真实 Android 实体机覆盖安装验证；
5. `flutter build apk --release`：构建成功，并在 OnePlus 9 覆盖安装验证短文本翻译及两种语言列表；先前构建的 AAB 尚未按本次修复重新验证。
