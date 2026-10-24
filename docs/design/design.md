# moonfig 设计

主线是「多 Source → 统一表示 → 分层合并 → 取值 / 提取到结构体」，先做能跑通的最小闭环。

## 1. 核心类型

```moonbit
///| 配置值在内存里的形状
pub enum ValueKind {
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
}
```

## 2. 合并

```moonbit
fn merge(base : Value, over : Value) -> Value
```

三条规则：

- 都是 `Table` → 递归逐 key 合并
- 其它 → `over` 覆盖 `base`
- 数组**整体替换**，不拼接

## 3. 配置对象与取值

```moonbit
let cfg = Config::new()
  .add(MemorySource::new(table))
  .add(JsonSource::from_str(text))
  .build()                       // 依次合并，后加者优先

cfg.get_string("db.host")        // String
cfg.get_int("db.port")           // Int64
cfg.get_bool("debug")            // Bool
cfg.get_bytes("cert")            // Bytes
```

- 路径用点号展开：`"db.host"` → `Table{"db": Table{"host": ...}}`
- key 不存在 → **报错，不返回默认值**（默认值应该由 `MemorySource` 提供，那才是它的职责）

## 4. 错误

```moonbit
pub suberror ConfigError {
  MissingKey(String)                      // 路径没被任何 Source 提供
  TypeMismatch(String, String, String)    // 路径、想要、实际
  ParseError(String)                      // 文本解析失败（包住 @json.JsonDecodeError）
  MergeConflict(String, String, String)   // 类型冲突：路径、两侧类型
}
```

唯一体验标准：用户看到错误，能立刻知道**哪个键、期望什么、实际什么**。

## 设计文档

- [sources.md](sources.md) —— Source 接口、package 划分、第三方解析器的取舍
- [extract.md](extract.md) —— 提取到结构体、整数映射、错误消息
- [../decisions/decisions.md](../decisions/decisions.md) —— 决策记录
