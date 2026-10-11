# config-moon 路线图

纯参考用。记录「按什么顺序做、每步做完能验收什么」，不是契约，可以随时改。

设计细节见 `docs/design.md`。

---

## 原则

三个约束决定了顺序：

1. **核心不依赖任何东西**，包括 `Json`。所以先做 `Value` 和合并，能独立测试。
2. **`Json` 只在最后一步出现**，是唯一有精度风险的地方。放最后，前面稳了再碰。
3. **每步都能单独跑通测试**，不留「等下一步才能验证」的半成品。

---

## 阶段一：核心骨架

做完就能用（来源只有内存和 JSON 文本）。

### 步骤 1 —— `value.mbt` + `error.mbt`

把「配置在内存里的形状」和错误类型定下来。

```moonbit
pub enum ValueKind {
  Null
  Bool(Bool)
  Int(Int64)              // 所有整数统一用 Int64
  Float(Double)
  Str(String)
  Array(Array[Value])
  Table(Map[String, Value])
}

pub struct Value {
  kind : ValueKind
}
```

**验收**：构造几个 `Value`，`debug_inspect` 打出来形状对。

**这步不做**：不合并、不碰 Json、不做取值 API。

### 步骤 2 —— `merge.mbt`

```moonbit
fn merge(base : Value, over : Value) -> Value
```

三条规则：都是 `Table` 就递归逐 key 合并；其它情况 `over` 覆盖 `base`；数组整体替换不拼接。

**验收**：手写几个嵌套 `Table`，验证「后覆盖前」「嵌套表不整体替换而是逐 key 合并」「数组整体换」。

**这步不做**：不记录来源、不做优先级列表。

### 步骤 3 —— `source.mbt` + `config.mbt`

定义来源 trait，加一个最简单的实现，再组装起来。

```moonbit
pub(open) trait Source {
  fn collect(Self) -> Value raise ConfigError
}
```

`MemorySource`（直接塞一棵 `Table`）先跑通全流程，**不碰文件、不碰 env、不碰格式**。

用户侧：

```moonbit
let cfg = Config::new()
  .add(MemorySource::new(...))
  .add(MemorySource::new(...))
  .build()

cfg.get_string("db.host")
cfg.get_int("db.port")
cfg.get_bool("debug")
```

路径用点号展开：`"db.host"` 找到 `Table{"db": Table{"host": ...}}`。

**验收**：两个 `MemorySource` 合起来，`get_*` 取到值；缺 key 报 `MissingKey`，报清晰的错而不是返回默认值或崩。

**到这里，库已经能用了。** 这是第一个可交付的里程碑。

---

## 阶段二：格式与提取

每个分支互不阻塞，可以只做一部分就发布。

### 步骤 4 —— `convert.mbt`（JSON 文本来源）

`JsonSource::from_str(text)`：文本 → `Json` → `Value`。用 core 的 `@json`，零第三方依赖。

**第一个真格式。**

**坑**：`Json` 的 `Number` 要按有没有小数分开处理成 `Int` / `Float`；`Number` 自带的 `repr` 字段可以用来还原大整数。

**验收**：一个 JSON 文本读进来，和取值 API 配合正常。

### 步骤 5 —— `extract`（提取到结构体）

```moonbit
pub fn[T : FromJson] extract(v : Value) -> T raise ConfigError
```

实现只有一句：`@json.from_json(v.to_json())`。

**转换规矩**（已实测）：

| ValueKind | → Json |
|---|---|
| `Int` | `Json::string(...)`，**不是** `Json::number` |
| `Float` | `Json::number` |
| `Bool` | `Json::bool` |
| `Str` | `Json::string` |
| `Null` | `Json::null` |
| `Array` / `Table` | 递归 |

`Int` 走字符串的根据：core 自己把 `Int64` 序列化成 JSON 字符串，且 `FromJson for Int64` 只吃字符串。双向对称，大整数无损。

**验收**：大整数（`9007199254740993`）端到端不丢；`Missing` 的 key 落到用户字段前先报错，不能静默变 `Null`。

**这一步是可选的便利层。** 不想要「提取到结构体」，可以整个跳过，库仍然完整。

---

## 阶段三：更多来源

### 步骤 6 —— 环境变量来源

`EnvSource`：把 `APP_DB_PORT=5432` 变成 `db.port`。

**这是坑最多的一步**，因为 env 全是字符串：

- 类型推断**必须在这一步做完**（`"5432"` → `Int`，`"true"` → `Bool`）。已实测：core 的 `Bool::from_json` 拒收字符串、`Double::from_json` 拒收字符串，等到提取那一步就晚了。
- 分隔符约定要定：`_` 变 `.`？大小写敏感？
- 前缀、空值、列表值的处理。

**验收**：`APP_DB_PORT=5432` 与 JSON 文件里的 `db.port` 正确合并，env 赢。

### 步骤 7 —— TOML 来源

`FileSource` + 第三方 TOML 解析器 → `Value`。

**到这一步，TOML 日期才有意义**：`Value` 里要有日期类型才能原样带到用户手上。如果走提取那条路，用户字段就只能是 `String`（`Json` 没有日期类型）。这是要接受的取舍。

---

## 阶段四：可选增强

下面每一项都是纯附加价值，前面任何一步都不依赖它。

### 诊断

回答「这个值到底从哪来的」。

**注意**：来源追踪**要么从步骤 1 就在 `Value` 里，要么这个库就不做**。没有「先做核心、以后再补」这个中间态——因为补的时候会改到 `Value` 的定义（每个值多带一个来源字段），而 `Value` 是所有东西的地基，前面全要跟着改。设计文档里目前选择了不做。

### 其它

- 数组拼接合并
- 序列化回写（配置 → 文件）
- 按 profile / 环境分节继承

---

## 依赖关系

```
步骤1 Value ──→ 步骤2 合并 ──→ 步骤3 Source+Config   ← 第一个可用里程碑
                                      │
                        ┌─────────────┼─────────────┬───────────┐
                        ▼             ▼             ▼           ▼
                   步骤4 JSON    步骤5 extract   步骤6 env   步骤7 TOML
                   （零依赖）    （碰 Json）     （坑多）    （第三方）
```

步骤 1~3 是主干，之后每个来源都是并联分支，互不阻塞。

---

## 已知的坑（实测记录）

| 实测 | 结果 | 影响 |
|---|---|---|
| `@json.parse("9007199254740993")` | `Number(9007199254740992, repr=Some(9007199254740993))` | 超出精确整数范围时 `repr` 留着原文 |
| `@json.parse("30")`、`@json.parse("1.5")` | `repr` 均为 `None` | 常见情况拿不到原文，只能按值判断整数／浮点（详见 `docs/design.md` 第 10 节更正） |
| `from_json` 到 `Double`，输入字符串 `"1.5"` | 失败 `Double::from_json: expected number` | 字符串自动转数字在 Json 层做不到 |
| `from_json` 到 `Bool`，输入字符串 `"true"` | 失败 `Bool::from_json: expected boolean` | 同上 |
| `from_json` 到 `Int`，输入 `5432.7` | 成功，得 `5432` | **静默截断**，不报错 |
