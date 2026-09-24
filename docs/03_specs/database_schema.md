# 数据库与持久化规格说明 (Database Schema Spec)

> **适用范围**：`lib/core/database/local_store.dart` 与 `lib/features/history/`  
> **底层驱动**：`sqflite` + `path`  
> **数据库文件名**：`xiaoan_tsl.db` (应用专属沙盒路径)  
> **当前版本**：`1`

---

## 1. 数据表结构 (DDL)

### 1.1 翻译历史表：`history_records`

存储所有本地翻译成功的历史记录及收藏标记。

```sql
CREATE TABLE history_records (
    id TEXT PRIMARY KEY,
    original_text TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    source_lang TEXT NOT NULL,
    target_lang TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    engine TEXT NOT NULL DEFAULT 'mlkit'
);

-- 索引：加速按时间倒序排列与按收藏状态筛选
CREATE INDEX idx_history_created_at ON history_records (created_at DESC);
CREATE INDEX idx_history_is_favorite ON history_records (is_favorite);
```

#### 字段约束与数据字典
| 字段名 | 字段类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | `TEXT` | `PRIMARY KEY` | 稳定唯一标识符（UUID v4 格式字符串） |
| `original_text` | `TEXT` | `NOT NULL` | 用户输入的翻译原文 |
| `translated_text` | `TEXT` | `NOT NULL` | 机器产出的译文内容 |
| `source_lang` | `TEXT` | `NOT NULL` | 规范化源语言代码（如 `'zh'`, `'en'`） |
| `target_lang` | `TEXT` | `NOT NULL` | 规范化目标语言代码（如 `'en'`, `'zh'`） |
| `created_at` | `INTEGER` | `NOT NULL` | 记录创建时间戳（毫秒级 Epoch 整数） |
| `is_favorite` | `INTEGER` | `NOT NULL DEFAULT 0` | 收藏状态：`1` 为已收藏，`0` 为未收藏 |
| `engine` | `TEXT` | `NOT NULL DEFAULT 'mlkit'`| 翻译引擎标记：`'mlkit'`（真机端侧）或 `'demo'`（早期演示/测试数据） |

---

### 1.2 应用设置表：`app_settings`

采用轻量通用的 Key-Value 模式存储用户自定义配置与系统标记。

```sql
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

#### 预置配置键说明
| 配置 Key | 取值范围 | 默认值 | 作用与生命周期 |
|---|---|---|---|
| `default_target_lang` | 任意有效语言代码 (如 `'zh'`, `'en'`) | `'zh'` | 每次启动应用或进入翻译页时的初始目标语言 |
| `theme_mode` | `'system'` \| `'light'` \| `'dark'` | `'system'` | 应用主题外观模式 |
| `json_migrated` | `'true'` \| `'false'` | 不存在 | 标记旧版 `translation_history.json` 是否已成功导入 |

---

## 2. 旧版 JSON 数据迁移规格

为保证从早期开发版平滑升级，系统在首次打开数据库时自动执行迁移：

1. **检测文件**：检测应用内部存储路径下是否存在 `translation_history.json`；
2. **幂等性检查**：查询 `app_settings` 表中是否存在 `json_migrated == 'true'`。若已存在，直接跳过迁移；
3. **事务执行**：
   * 开启 SQLite 事务 `db.transaction(...)`；
   * 读取 JSON 数组，将旧数据映射为 `history_records` 插入 SQL，保留原有的收藏状态与时间戳；
   * 在同一事务中向 `app_settings` 写入 `('json_migrated', 'true')`；
4. **安全保护**：
   * 迁移过程中若发生 JSON 解析失败或 SQL 异常，事务自动回滚，**严禁**删除或覆盖旧 JSON 文件；
   * 迁移成功后，保留原 JSON 文件作为安全备份，后续写入仅面向 SQLite 数据库。

---

## 3. 数据操作与防抖规则

1. **短时提交防抖合并**：
   在写入新历史记录时，若在过去 **30 秒** 内已存在相同 `original_text`、`source_lang` 和 `target_lang` 的记录，执行 `UPDATE` 更新其 `created_at` 与 `translated_text`，而不插入新行。
2. **模糊搜索规格**：
   历史搜索必须采用参数化查询，防范 SQL 注入：
   ```sql
   SELECT * FROM history_records 
   WHERE original_text LIKE ? OR translated_text LIKE ? 
   ORDER BY created_at DESC 
   LIMIT 100;
   -- 参数: ['%$keyword%', '%$keyword%']
   ```
3. **数据清空机制**：
   清空历史执行 `DELETE FROM history_records;`；该操作需在 UI 弹窗二次确认后方可执行。
