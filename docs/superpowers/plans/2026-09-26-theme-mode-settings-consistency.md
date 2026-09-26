# 外观模式设置交互与应用语言对齐实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将设置页中的“外观模式”显示和选择调整为与“应用语言”完全一致（ListTile 显示副标题和右箭头，点击整行触发 SimpleDialog 单选弹窗并展示选中项对勾标记）。

**架构：** 修改 `SettingsPage` 中“外观模式”的 `ListTile` 构造，引入 `subtitle` 响应当前主题模式名称，将 `trailing` 从 `DropdownButton<ThemeMode>` 替换为 `Icons.chevron_right`，在 `onTap` 中通过 `showDialog<ThemeMode>` 呼出与“应用语言”对齐的 `SimpleDialog` 单选弹窗，调用 `AppController.setThemeMode` 进行即时切换与持久化存储。在 `test/widget_test.dart` 中适配现有测试并补充针对弹窗和副标题的用例。

**技术栈：** Flutter, Riverpod (`flutter_riverpod`), `AppLocalizations`, Flutter Widget Test (`flutter_test`).

---

### 文件结构与职责

- 修改：`test/widget_test.dart`
  - 职责：适配既有主题切换测试用例，增加外观模式 ListTile 副标题及 SimpleDialog 弹窗选择、勾选标记的测试。
- 修改：`lib/features/settings/settings_page.dart`
  - 职责：更新设置页外观模式 UI 结构与点击弹窗交互。
- 修改：`docs/CHANGELOG.md`
  - 职责：登记本次交互改进的文档记录。

---

### 任务 1：更新与补充自动化测试（TDD）

**文件：**
- 修改：`test/widget_test.dart:385-405`
- 修改：`test/widget_test.dart:660-675`
- 新增测试用例至 `test/widget_test.dart` 末尾

- [x] **步骤 1：编写失败的测试**

在 `test/widget_test.dart` 中：
1. 更新用例 `设置主题和次级页面可返回`：
```dart
    await tester.tap(find.widgetWithText(ListTile, '外观模式'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(SimpleDialogOption, '深色'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).themeMode == ThemeMode.dark,
    );
```
2. 更新用例 `默认语言与主题在重建后恢复`：
```dart
    await tester.tap(find.widgetWithText(ListTile, '外观模式'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(SimpleDialogOption, '浅色'));
    await waitFor(
      tester,
      () => container.read(appControllerProvider).themeMode == ThemeMode.light,
    );
```
3. 新增用例 `设置中外观模式显示副标题且支持通过弹窗切换与勾选`：
```dart
  testWidgets('设置中外观模式显示副标题且支持通过弹窗切换与勾选', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    // 初始状态下外观模式显示副标题“跟随系统”
    final themeTile = find.widgetWithText(ListTile, '外观模式');
    expect(themeTile, findsOneWidget);
    expect(find.descendant(of: themeTile, matching: find.text('跟随系统')), findsOneWidget);

    // 点击外观模式整行，弹出 SimpleDialog
    await tester.tap(themeTile);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);

    // 验证当前“跟随系统”选项带有勾选图标
    final systemOption = find.widgetWithText(SimpleDialogOption, '跟随系统');
    expect(
      find.descendant(of: systemOption, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    // 点击“深色”选项
    await tester.tap(find.widgetWithText(SimpleDialogOption, '深色'));
    await tester.pumpAndSettle();

    // 弹窗关闭，主题切换为深色，副标题更新为“深色”
    expect(find.byType(SimpleDialog), findsNothing);
    expect(container.read(appControllerProvider).themeMode, ThemeMode.dark);
    expect(find.descendant(of: themeTile, matching: find.text('深色')), findsOneWidget);
  });
```

- [x] **步骤 2：运行测试验证失败**

运行：`flutter test test/widget_test.dart --name "设置中外观模式显示副标题且支持通过弹窗切换与勾选"`
预期：FAIL，因为此时设置页中尚未提供 SimpleDialog 弹窗和 subtitle。

---

### 任务 2：实现设置页外观模式与应用语言一致的交互

**文件：**
- 修改：`lib/features/settings/settings_page.dart:34-58`

- [x] **步骤 1：编写最少实现代码**

将 `lib/features/settings/settings_page.dart` 中原有的外观模式 `ListTile`：
```dart
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.themeModeLabel),
            trailing: DropdownButton<ThemeMode>(
              value: state.themeMode,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(l10n.themeModeSystem),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(l10n.themeModeLight),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(l10n.themeModeDark),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) controller.setThemeMode(mode);
              },
            ),
          ),
```
替换为与应用语言完全一致的展示与 SimpleDialog 弹窗结构：
```dart
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.themeModeLabel),
            subtitle: Text(
              switch (state.themeMode) {
                ThemeMode.system => l10n.themeModeSystem,
                ThemeMode.light => l10n.themeModeLight,
                ThemeMode.dark => l10n.themeModeDark,
              },
            ),
            trailing: const Icon(Icons.chevron_right),
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
          ),
```

- [x] **步骤 2：运行测试与静态分析验证通过**

运行：`flutter test`
预期：PASS（全量测试通过，包含新增的组件测试）

运行：`flutter analyze`
预期：No issues found!

---

### 任务 3：更新文档并提交 Commit

**文件：**
- 修改：`docs/CHANGELOG.md`
- 修改：`docs/superpowers/plans/2026-09-26-theme-mode-settings-consistency.md`

- [x] **步骤 1：在 `docs/CHANGELOG.md` 记录本次实现与测试证据**
- [x] **步骤 2：暂存相关文件并提交 Commit**
```bash
git add lib/features/settings/settings_page.dart test/widget_test.dart docs/CHANGELOG.md docs/superpowers/plans/2026-09-26-theme-mode-settings-consistency.md
git commit -m "feat: 外观模式的显示和选择调整为和应用语言一致"
```
