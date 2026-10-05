# 小安翻译 (Xiaoan TSL) 平板端（iPad 与 Android 平板）适配技术方案与设计指南

> **状态**：Draft / Design Specification  
> **适用版本**：v1.1+  
> **目标设备**：Apple iPad 全系列 (iPadOS 14+)、Android 平板与折叠屏展开态 (Android 12L / API 32+)  
> **核心原则**：摆脱“大号手机”模式，基于窗口尺寸断点（Window Size Classes）驱动自适应布局与双栏分屏体验。

---

## 1. 现状痛点与适配目标

### 1.1 移动端现有架构在大屏上的局限（“大号手机”反模式）
当前小安翻译已在 Android/iOS 手机端完成良好的基础功能闭环，但在平板（如 10.9~13 英寸 iPad、Android 平板）上直接运行时存在以下明显体验缺陷：
1. **单一垂直流拉伸**：翻译首页、历史记录、设置等页面均为单列 100% 撑满布局。在宽屏横屏下，卡片和按钮横向跨度达到 1000~1300dp，单行文本过长，严重违背人类阅读舒适度（每行 60~75 字符最佳）。
2. **底部导航栏触控困难**：底部 `NavigationBar` 在大屏设备上横向跨度过宽，双手握持平板或置于桌面支架时，大拇指难以舒适触碰中间菜单项。
3. **主业务区空间浪费**：翻译主功能（输入框与结果面板）上下堆叠。在宽屏环境下，左右两侧有大片横向留白，而纵向高度受限，无法同时舒适展示长文本原文与译文。
4. **浏览流易被打断**：历史记录和收藏列表点击某项后全屏跳回首页，无法像现代平板应用一样在大屏上实现“左边看列表、右边看详情”的 Master-Detail 连贯浏览。
5. **iPad 原生崩溃隐患（致命）**：`SharingService` 直接调用系统分享面板，未指定 `sharePositionOrigin` 锚点 Rect。在 iPadOS 下，系统必须通过 Popover 弹出分享菜单，缺少锚点会导致应用直接崩溃。

### 1.2 核心适配设计原则
- **动态断点优先，拒绝硬件硬编码**：不通过 `Platform.isIOS` 或设备型号判断是否为平板；纯粹根据当前应用窗口的**可用宽度（Window Width）**进行动态响应式渲染。
- **无缝支持分屏多任务（Multitasking）**：完整适配 iPadOS Split View（1/3、1/2、2/3 分屏）、Slide Over、Stage Manager（台前调度）以及 Android 平板的多窗口模式。当用户在 iPad 上拖动为 1/3 窄条窗口时，界面平滑降级为手机形态；拖回全屏时无缝升级为双栏大屏形态。
- **符合平台设计规范**：遵循 Google Material 3 Adaptive Layout 准则与 Apple Human Interface Guidelines for iPadOS。

---

## 2. 窗口尺寸断点体系（Window Size Classes）

根据主流响应式设计规范，将小安翻译的视口宽度划分为 3 个核心断点层级：

| 断点等级 (Size Class) | 视口宽度区间 (Width) | 典型设备与使用场景 | 导航布局方式 | 翻译页布局模式 |
| :--- | :--- | :--- | :--- | :--- |
| **Compact (紧凑型)** | `< 600dp` | 所有手机竖屏、大屏折叠外屏、iPad 1/3 窄分屏、Android 窄分屏 | 底部导航栏 (`NavigationBar`) | 单列上下垂直流堆叠 |
| **Medium (中等型)** | `600dp ≤ W < 840dp` | 小尺寸平板竖屏 (iPad mini)、主流大手机横屏、iPad 1/2 分屏 | 左侧边导航轨 (`NavigationRail`) | 双栏紧凑对照或自适应流 |
| **Expanded (扩展型)** | `≥ 840dp` | iPad / Android 平板横屏、大尺寸平板竖屏、桌面窗口 | 左侧边导航轨 (`NavigationRail`) | 左右并排双面板对照 (Side-by-Side) |

---

## 3. 全局导航框架自适应改造（Adaptive Shell）

### 3.1 导航结构演进
在 `lib/core/router/app_router.dart` 的 `StatefulShellRoute` 外壳层，根据当前断点自适应切换导航呈现方式：

```text
[Compact 模式 (< 600dp)]            [Medium / Expanded 模式 (≥ 600dp)]
┌────────────────────────┐         ┌──────┬──────────────────────────────────┐
│      App Bar           │         │ 侧   │            App Bar               │
├────────────────────────┤         │ 边   ├──────────────────────────────────┤
│                        │         │ 导   │                                  │
│      当前页面内容       │   ──►   │ 航   │            当前页面内容           │
│                        │         │ 栏   │                                  │
├────────────────────────┤         │ Rail │                                  │
│   底部 NavigationBar   │         └──────┴──────────────────────────────────┘
└────────────────────────┘
```

### 3.2 导航交互规范
- **Compact 宽度**：保留现有的 Material 3 底部导航条（高度 80dp，4 个入口）。
- **Medium / Expanded 宽度**：
  - 隐藏底部栏，转为左侧固定宽度的 `NavigationRail`（宽度约 72~80dp）。
  - 侧边栏垂直居中或靠顶排列 4 个入口图标与标签（翻译、历史、收藏、设置）。
  - 针对平板双手握持，左手大拇指即可在左侧极度轻松地切换一级功能。

---

## 4. 核心页面针对性适配方案

### 4.1 翻译首页（TranslationHomePage）：左右双栏对照模式

#### (1) 视觉与布局重塑
- **Compact 模式**：保留原有的单列卡片垂直堆叠。
- **Expanded / Medium 宽屏模式**：
  - **顶部**：紧凑型语言控制面板，包含源语言按钮、对调箭头、目标语言按钮，最大宽度约束为 600dp 居中摆放。
  - **主内容区**：采用左右双栏布局（`Row` + 两侧 `Expanded`），两侧各放置一个 `AppPanel`：
    - **左侧输入栏**：
      - 顶部显示“原文”标签与自动语种识别结果（如“检测为英语”）。
      - 中间为自适应拉伸的多行文本输入框（`TextField`），高度充分伸展，支持长篇文本编辑。
      - 底部工具栏包含字符统计（如 `128 / 5000`）、原文朗读按钮、一键清空按钮、即时翻译/状态按钮。
    - **右侧译文栏**：
      - 顶部显示“译文”标签与翻译引擎状态（如“离线本地模型”）。
      - 中间为大号可选中译文展示区（`SelectableText`），随输入实时呈现或点击翻译后刷新。
      - 底部工具栏右对齐展开：译文朗读、收藏、一键复制、系统分享等快捷图标。
  - **超宽屏居中约束**：对于 12.9 英寸等超大平板（横屏分辨率高达 1366dp），将整个工作区包裹在 `ConstrainedBox(maxWidth: 1200)` 并居中，防止面板过于宽扁。

```text
┌────────────────────────────────────────────────────────────────────────┐
│                              小安翻译                                   │
│            [ 英语 (自动检测) ]  ⇄ (互换)  [ 中文 (简体) ]                │
├───────────────────────────────────┬────────────────────────────────────┤
│ 左侧：原文输入 (Source)            │ 右侧：目标译文 (Target)             │
│ ┌───────────────────────────────┐ │ ┌────────────────────────────────┐ │
│ │ Please enter the text to      │ │ │ 请在此输入需要翻译的文本...      │ │
│ │ translate here...             │ │ │                                │ │
│ │                               │ │ │                                │ │
│ │                               │ │ │                                │ │
│ │                               │ │ │                                │ │
│ ├───────────────────────────────┤ ├────────────────────────────────┤ │
│ │ 32 / 5000  [朗读] [清空]      │ │ ML Kit 本地离线引擎              │ │
│ │                 [ 翻译按钮 ]  │ │          [朗读] [收藏] [复制] [分享]│ │
│ └───────────────────────────────┘ │ └────────────────────────────────┘ │
└───────────────────────────────────┴────────────────────────────────────┘
```

---

### 4.2 历史记录与收藏页（RecordsPage / FavoritesPage）：Master-Detail 主从分栏

#### (1) 交互问题
在手机上，列表项通常是一张卡片，点击后通过路由跳回首页载入该条记录。但在平板宽屏上，用户期望能够快速滚动历史/收藏，一边浏览一边对照查阅。

#### (2) Expanded 双栏主从设计
- **左侧主列表栏 (Master Pane，固定宽 360~400dp)**：
  - 顶部集成搜索框（支持实时搜索过滤）。
  - 下方为紧凑型历史/收藏列表。列表项显示简短原文、译文预览及时间。
  - 支持选中高亮状态（`selected: item.id == activeRecordId`）。
- **右侧详情展示栏 (Detail Pane，弹性填充剩余空间)**：
  - 展示当前选中记录的完整双语对照大卡片。
  - 顶部带有语种标签与时间戳。
  - 原文与译文均支持大字号排版、独立朗读、复制、收藏状态切换。
  - 提供“在首页编辑/重译”快捷操作按钮。
  - 当无任何记录或未选中时，右侧展示轻量级空态插画与提示（“从左侧列表中选择一条记录以查看详情”）。

---

### 4.3 设置中心与次级页面：最大内容宽度居中（Max-Content Constraint）

#### (1) 适用页面
- 设置页（`SettingsPage`）
- 关于页面（`AboutPage`）
- 隐私政策（`PrivacyPolicyPage`）
- 开源许可协议（`OpenSourceLicensesPage`）
- 离线模型管理（`OfflineModelsPage`）

#### (2) 适配方案
- 在 Medium / Expanded 宽屏环境下，如果直接让 `ListTile` 撑满整个屏幕宽度，左侧图标与右侧操作箭头相距近一米，视觉体验极其割裂。
- **解决方案**：统一使用内容最大宽度包裹容器 `MaxContentWidthContainer`（推荐 `maxWidth: 680~760dp`），并在水平方向居中（`Alignment.center`）。
- **语言选择页（LanguagePage）网格化**：
  - 手机上是单列长列表滚动；
  - 平板宽屏上可将语言列表调整为双列或三列网格（`GridView.builder`），使 50+ 种语言在 1~2 屏内即可快速浏览与点击，减少冗长的翻页滚动。

---

## 5. 原生工程配置与已知缺陷规避（关键要点）

### 5.1 iOS / iPadOS 关键配置与崩溃防范
1. **防止 `share_plus` 在 iPad 上致命崩溃（Top 1 必改项）**：
   - **问题根源**：在 iPadOS 上，系统分享菜单由 `UIPopoverPresentationController` 呈现，必须提供锚点视图或矩形区域；若未指定 `sharePositionOrigin`，系统调用会抛出异常导致应用瞬间闪退。
   - **防御方案**：在各调用分享的组件（如 `TranslationHomePage`、`RecordsPage`）中，通过 `context.findRenderObject() as RenderBox?` 计算当前点击分享按钮在屏幕上的全局坐标与尺寸，传递给 `SharingService.shareTranslation(..., sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size)`。
2. **多任务与分屏支持（Multitasking）**：
   - 检查 `ios/Runner/Info.plist`，确保 `UIRequiresFullScreen` 设为 `false`（或不显式锁定为 true），允许系统启用 Split View 与 Slide Over。
   - `UISupportedInterfaceOrientations~ipad` 已经包含全部 4 个方向（竖屏、倒置竖屏、左横屏、右横屏），保持该配置。
3. **Xcode Target Device Family**：
   - 当前项目已在 `project.pbxproj` 中配置 `TARGETED_DEVICE_FAMILY = "1,2"`，代表同时支持 iPhone 与 iPad，无需额外改动。

### 5.2 Android 平板关键配置
1. **支持自由多窗口与动态尺寸变化**：
   - 在 `android/app/src/main/AndroidManifest.xml` 中，主 Activity 的 `android:configChanges` 已涵盖 `orientation|screenSize|smallestScreenSize|screenLayout|density`。
   - 这确保了用户在旋转平板、从全屏拖动为半屏分屏、或在折叠屏展开折叠时，Flutter 引擎直接平滑触发布局重新计算，而不会导致 Android Activity 重新销毁重建。
2. **平板大屏适配属性**：
   - 确认 `<application>` 标签支持 `android:resizeableActivity="true"`（Android 7.0+ 默认即为 true）。

---

## 6. 平板专属外设与交互增强（Keyboard & Trackpad）

平板用户常连接蓝牙键盘（如 iPad 妙控键盘、罗技键盘）或触控板/鼠标使用，应提供桌面级的交互顺畅感：

1. **快捷键系统（Shortcuts & Actions）**：
   - `Cmd + Enter` / `Ctrl + Enter`：在输入框内直接触发即时翻译。
   - `Cmd + F` / `Ctrl + F`：在历史记录/收藏页直接聚焦搜索输入框。
   - `Esc`：快速清空输入内容或关闭弹窗。
2. **指针与悬停效果（Hover Effects & Cursors）**：
   - 为页面中所有按钮、卡片、列表项添加鼠标悬停（Hover）视觉反馈与 `SystemMouseCursors.click` 鼠标手型指示，改善使用触控板/鼠标时的交互反馈。
3. **焦点导航（Focus Traversal）**：
   - 确保键盘 `Tab` 键能以逻辑顺序在“语言切换 -> 原文输入框 -> 翻译按钮 -> 结果操作按钮”之间移动焦点。

---

## 7. 实施路线图（三阶段推进计划）

| 阶段 | 核心任务 | 涉及模块与文件 | 预期交付与验证 |
| :--- | :--- | :--- | :--- |
| **阶段一：基建与安全防线** | 1. 修复 iPad 分享弹窗崩溃隐患，添加 `sharePositionOrigin`<br>2. 封装响应式断点工具类与 `MaxContentWidthContainer` | `lib/services/sharing/`<br>`lib/core/widgets/` | iPad 模拟器与真机上测试分享功能不崩溃；建立统一断点规范 |
| **阶段二：自适应导航与双栏首页** | 1. `app_router.dart` 导航壳层自适应切换（`NavigationBar` ⇄ `NavigationRail`）<br>2. `TranslationHomePage` 宽屏左右双栏对照重塑 | `lib/core/router/`<br>`lib/features/translate/` | 平板横屏/竖屏及分屏模式下，导航与翻译双栏布局平滑无缝响应 |
| **阶段三：次级页主从与外设增强** | 1. 历史/收藏页 Master-Detail 双栏适配<br>2. 设置页与语言选择页最大宽度/网格重塑<br>3. 物理键盘常用快捷键支持 | `lib/features/history/`<br>`lib/features/settings/`<br>`lib/features/language/` | 完整的全页面平板级体验，全量自动化组件测试覆盖并完成回归 |
