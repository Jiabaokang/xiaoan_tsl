# 外观模式设置交互与应用语言对齐设计规范

## 1. 概述与背景

小安翻译设置页中，各主要偏好设置项均采用统一的 `ListTile` 交互范式：
- 图标（leading）
- 标题（title）
- 当前生效值的描述文本（subtitle）
- 右向指示箭头（trailing: `Icons.chevron_right`）
- 点击整行触发进一步选择（通过路由跳转或弹出单选对话框）

其中，“应用语言”设置项已采用标准的 `SimpleDialog` 单选弹窗，用户点击后展示系统语言、简体中文、英文选项，并对当前已选项展示勾选图标（`Icons.check`）。
而“外观模式”此前直接在 `ListTile` 的 `trailing` 中嵌入了 `DropdownButton<ThemeMode>`，没有展示 `subtitle`，且存在交互热区较小、缺少右箭头视觉线索、与“应用语言”等其他设置项视觉与交互风格不一致的问题。

本规范定义将“外观模式”的显示和选择调整为与“应用语言”完全一致的实现标准。

## 2. 详细设计

### 2.1 界面与组件结构（`lib/features/settings/settings_page.dart`）

“外观模式”对应的 `ListTile` 调整如下：
1. **图标（leading）**：保持 `const Icon(Icons.dark_mode_outlined)`。
2. **标题（title）**：保持 `Text(l10n.themeModeLabel)`。
3. **副标题（subtitle）**：新增 `subtitle`，显示当前选中的外观模式文本：
   ```dart
   subtitle: Text(
     switch (state.themeMode) {
       ThemeMode.system => l10n.themeModeSystem,
       ThemeMode.light => l10n.themeModeLight,
       ThemeMode.dark => l10n.themeModeDark,
     },
   ),
   ```
4. **尾部（trailing）**：替换原有的 `DropdownButton<ThemeMode>` 为 `const Icon(Icons.chevron_right)`。
5. **点击事件（onTap）**：点击整行弹出 `SimpleDialog`，返回选中的 `ThemeMode`：
   ```dart
   onTap: () async {
     final selected = await showDialog<ThemeMode>(
       context: context,
       builder: (dialogContext) => SimpleDialog(
         title: Text(l10n.themeModeLabel),
         children: [
           SimpleDialogOption(
             onPressed: () => Navigator.pop(dialogContext, ThemeMode.system),
             child: Row(
               children: [
                 Expanded(child: Text(l10n.themeModeSystem)),
                 if (state.themeMode == ThemeMode.system)
                   const Icon(Icons.check, size: 20),
               ],
             ),
           ),
           SimpleDialogOption(
             onPressed: () => Navigator.pop(dialogContext, ThemeMode.light),
             child: Row(
               children: [
                 Expanded(child: Text(l10n.themeModeLight)),
                 if (state.themeMode == ThemeMode.light)
                   const Icon(Icons.check, size: 20),
               ],
             ),
           ),
           SimpleDialogOption(
             onPressed: () => Navigator.pop(dialogContext, ThemeMode.dark),
             child: Row(
               children: [
                 Expanded(child: Text(l10n.themeModeDark)),
                 if (state.themeMode == ThemeMode.dark)
                   const Icon(Icons.check, size: 20),
               ],
             ),
           ),
         ],
       ),
     );
     if (selected != null) {
       await controller.setThemeMode(selected);
     }
   },
   ```

### 2.2 状态流与持久化

- 点击选项后，通过 `AppController.setThemeMode(selected)` 触发状态更新。
- 底层已通过 `LocalStore.setSetting('theme_mode', ...)` 完成数据库持久化，应用重建或重启后自动加载保存的模式。

### 2.3 国际化与文案契约

复用已有 `AppLocalizations` 定义，无需增加新字段：
- 标题：`themeModeLabel`（'外观模式' / 'Theme Mode'）
- 跟随系统：`themeModeSystem`（'跟随系统' / 'System'）
- 浅色：`themeModeLight`（'浅色' / 'Light'）
- 深色：`themeModeDark`（'深色' / 'Dark'）

### 2.4 自动化测试适配（`test/widget_test.dart`）

1. **测试用例 1：`设置主题和次级页面可返回`**
   - 现存逻辑通过点击文本“跟随系统”展开下拉框；
   - 调整为点击包含“外观模式”的 ListTile（`find.widgetWithText(ListTile, '外观模式')`），弹出 `SimpleDialog` 后，点击弹窗中的 `find.widgetWithText(SimpleDialogOption, '深色')` 完成切换；
   - 验证暗色模式亮度生效。
2. **测试用例 2：`默认语言与主题在重建后恢复`**
   - 同样将点击下拉框的操作调整为点击外观模式 ListTile 并从弹窗中选中“浅色”；
   - 验证在重新初始化和重建后正确恢复为浅色模式。
3. **新增针对性测试**
   - 验证外观模式设置项包含副标题且显示当前主题名称；
   - 验证点击打开弹窗、弹窗展示全部 3 个选项且当前模式带对勾；
   - 验证切换后副标题同步更新。

## 3. 验收标准

1. 设置页中“外观模式”展示格式与“应用语言”完全一致（leading 图标、title 标题、subtitle 当前选值、trailing 箭头）。
2. 点击“外观模式”弹出 `SimpleDialog`，包含系统、浅色、深色三项，选中项有对勾标识。
3. 点击各选项可即时切换主题模式并持久化存储，下次启动依然生效。
4. 全量 `flutter test` 和 `flutter analyze` 保持通过。
