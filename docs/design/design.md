# moonfig 设计

主线是「多 Source → 统一表示 → 分层合并 → 取值 / 提取到结构体」，先做能跑通的最小闭环。

## 1. 核心类型

```moonbit
///| 配置值在内存里的形状
pub(all) enum ValueKind {
  Null
  Bool(Bool)
  Int(Int64)              // 所有整数统一用 Int64
  Float(Double)
  Str(String)
  Bytes(Bytes)            // 二进制数据，只有 CBOR 这类二进制格式会产生
  Array(Array[Value])
  Table(Map[String, Value])
}

///| 配置值
pub struct Value {
  kind : ValueKind
  priv origin : &OriginSite?   // 来源对象；构造器给 None，合并前补上
}
```

`origin` 只存一个指向 `OriginSite` 的引用，不存 label 字符串。`OriginSite` 是来源自己的对象，
提供 `kind`、`describe(KeyPath)` 和可选的 `locator`；label 在 `Origin::label()` 里按需生成。

`Source::collect` 返回 `Layer { value, origin }`，一层的值和它的 site 一起产出。`Config` 把 site
递归补到整棵树；已经有 site 的节点不覆盖，组合来源可以先用 `Value::with_origin` 给子树标不同的 site。

`KeyPath` 是结构化的键路径（`["db", "port"]`），点号串只在 `origin_of` / `get_path` 的 API
边界解析一次；`origin_of` / `origins()` 返回 `Origin`，用 `path()` 拿层级，用 `label()` 拿展示文本。

`Value::from_literal(StringView)` 把一段字面文本猜成配置值（`Bool` / `Int64` / `Float` /
字符串），环境变量和命令行共用这一套，规则见 [sources.md](sources.md)。

## 2. 合并

```moonbit
fn merge(base : Value, over : Value) -> Value
```

三条规则：

- 都是 `Table` → 递归逐 key 合并
- 其它 → `over` 覆盖 `base`
- 数组**整体替换**，不拼接

## 3. 配置对象与取值

`Config` 持有 `sources`、`rule`、`value` 三个字段：`add` 只 append，`build` 按 `rule` 把 Source 逐个 merge 成一棵树，之后的 `get_*` 都从这棵树按路径取值。它不认识具体格式，只认识 `Source`。

`MergeRule` 默认 `LastWins`（后加覆盖先加），另有 `FirstWins`、`ByKind(Array[SourceKind])` 和 `Custom(fn)`。规则是整份 `Config` 的，不做单层特殊；要单层特殊就给 `Source` 包一层。`ByKind` 的数组按优先级从高到低写，没列出的 kind 排在最后，同一档内后加的赢；`Custom(fn)` 收到「已经合好的部分」和「下一层」，返回新的部分。

```moonbit
let cfg = Config::new()
  .add(MemorySource::new(table))
  .add(StringSource::new(text, JsonFormat::new()))
  .build()                       // 依次合并，后加者优先

cfg.get_string("db.host")        // String
cfg.get_int("db.port")           // Int64
cfg.get_float("ratio")           // Double
cfg.get_bool("debug")            // Bool
cfg.get_bytes("cert")            // Bytes
```

- 路径用点号展开：`"db.host"` → `Table{"db": Table{"host": ...}}`
- key 不存在 → **报错，不返回默认值**（默认值应该由 `MemorySource` 提供，那才是它的职责）

## 4. 错误

```moonbit
pub(all) suberror ConfigError {
  MissingKey(String)                      // 路径没被任何 Source 提供
  TypeMismatch(String, String, String)    // 路径、想要、实际
  ParseError(String)                      // 解析失败：格式、类型推断、整数溢出……
  IoError(String)                         // 读取外部数据失败（文件、环境变量……）
  MergeConflict(String, String, String)   // 类型冲突：路径、两侧类型；当前没有代码路径会抛
}
```

唯一体验标准：用户看到错误，能立刻知道**哪个键、期望什么、实际什么**。

`IoError` 和 `ParseError` 分开：读不到和读到了但解析不了是两回事，混在一起会让用户去查格式。
`MergeConflict` 是预留变体——现在的合并规则都是覆盖，不做类型冲突判定。

## 设计文档

- [sources.md](sources.md) —— Source / Format 模型、package 划分与来源追踪
- [extract.md](extract.md) —— 提取到结构体、整数映射、错误消息
- [../decisions/decisions.md](../decisions/decisions.md) —— 决策记录
