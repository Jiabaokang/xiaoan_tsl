# 路由与深链接规格说明 (Routing & DeepLink Spec)

> **适用范围**：`lib/core/router/app_router.dart`  
> **底层框架**：`go_router` (声明式路由)

---

## 1. 路由表与路径规范

### 1.1 底部导航四大常驻入口 (Shell / Stateful Navigation)
应用底部常驻 4 个主导航入口，切换标签时必须保持各页面内部状态（尤其是翻译主页的输入内容不重置）：

| 路由路径 | 页面组件 | 页面职责 |
|---|---|---|
| `/translate` | `TranslationHomePage` | 文本输入、语种切换、翻译结果与快捷操作 |
| `/history` | `RecordsPage(filterFavorites: false)` | 全部翻译历史记录浏览、搜索与单条/批量清理 |
| `/favorites` | `FavoritesPage` (复用 RecordsPage 视图) | 仅显示已星标收藏的历史记录列表 |
| `/settings` | `SettingsPage` | 主题外观、默认目标语种、清空历史、关于与隐私入口 |

---

### 1.2 次级页面与参数规格

#### 1. 语言选择页 (`/languages`)
* **路径**：`/languages`
* **Query 参数**：`mode` (字符串，可选值：`'source'` \| `'target'` \| `'default-target'`)
* **行为规则**：
  * 当 `mode == 'source'` 时，首项提供“自动检测”；
  * 当 `mode == 'target'` 或 `mode == 'default-target'` 时，**严禁显示“自动检测”**，仅展示具体的合法语言选项；
  * 支持按语言中文名或英文名进行输入过滤。

#### 2. 离线语言包管理页 (`/offline-models`)
* **路径**：`/offline-models`
* **Query 参数**：无
* **行为规则**：展示全量支持语言模型的本地状态，提供下载与删除交互。

#### 3. 关于与隐私页 (`/info`)
* **路径**：`/info`
* **Query 参数**：无
* **行为规则**：展示应用名称、图标、动态版本号/构建号、开源许可与外部隐私政策链接。

---

## 2. 深链接与历史恢复规格 (DeepLink Specification)

* **深链路径**：`/translate?record=<record_id>`
* **触发场景**：
  1. 用户在 `/history` 或 `/favorites` 列表中点击某条历史卡片；
  2. 外部通过 DeepLink 打开指定历史记录。
* **处理流程**：
  1. `app_router.dart` 解析 URL 中的 `record` 查询参数；
  2. 若 `record != null`，调用 `localStore.findRecordById(recordId)`；
  3. 若记录存在，将记录中的 `original_text`、`source_lang`、`target_lang` 和 `translated_text` 同步至 `appController`，无缝恢复界面显示；
  4. 若记录不存在，平滑进入默认空白 `/translate` 界面，不向用户抛出异常弹窗。

---

## 3. 错误路由与异常回退

对于任何未匹配的非法路径（如 `/unknown`、`/foo`）：
* 展示统一友好的 `NotFoundPage`；
* 页面居中提示“页面未找到”，并提供醒目的“返回首页”按钮，点击后重定向至 `/translate`。
