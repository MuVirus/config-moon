# 提取到结构体

## 1. 接口

```moonbit
pub fn[T : FromJson] extract(v : Value) -> T raise ConfigError
pub fn[T : FromJson] extract_from(cfg : Config, path : String) -> T raise ConfigError
pub fn[T : FromJson + Validate] extract_validated_from(cfg : Config, path : String) -> T raise ConfigError
```

`extract` 提取整棵树，`extract_from` 先按键取子树再提取；后者是自由函数，因为方法不能跨 package（见 [decisions.md](../decisions/decisions.md#2-方法不能跨包)）。`extract_validated_from` 在提取后调用结构体自己的 `Validate`，见 [validate.md](validate.md)。

实现主线是 `@json.from_json(to_json(v))`，但整数映射有一个绕不过去的矛盾：

| 字段类型 | MoonBit 标准库的 `from_json` 只认 |
|---|---|
| `Int` / `Int32` | `Json::Number`（±2^31 范围检查） |
| `Int64` / `UInt64` | `Json::String`（只吃字符串） |

`extract[T : FromJson]` 只有值级约束，看不到字段类型，所以一棵 Json 树不可能同时满足两者。取舍是：**统一映射成数字**，64 位字段用包装类型。

标准库的 `Int::from_json` 对数字只做范围检查，`3.14` 会被 `to_int()` 截断成 `3`。`extract` 在正常解码成功后，如果原值树里有浮点，会再用一棵把所有浮点换成字符串 `"NaN"` 的探针树解一次：`Double` / `Float` 接受 `"NaN"`，整数类型不接受，因此能定位到「浮点想进整数字段」并报 `TypeMismatch`。没有浮点的配置不会多跑这一遍，`Double` 字段仍返回原值，不受探针影响。

| ValueKind | → Json |
|---|---|
| `Int` | `Json::number(i.to_double(), repr=i.to_string())` |
| `Float` | `Json::number` |
| `Bool` | `Json::bool` |
| `Str` | `Json::string` |
| `Bytes` | `Json::string(...)`，走标准库的字节编码 |
| `Null` | `Json::null` |
| `Array` / `Table` | 递归 |

`repr` 是标准库自己的字段：`Json::stringify` 优先写它，所以 `to_json(Value::int(9007199254740993L)).stringify()` 仍是原文 `9007199254740993`，不经过 `Double` 丢精度。`Int64Text` / `UInt64Text` 也读它，结构体里的 64 位字段写 `id : Int64Text`，`to_int64()` 取回原值。

解析侧与实测数据见 [decisions.md](../decisions/decisions.md#4-json-数值的边界)。

另一个代价：`Double` 字段收到超出 2^53 的整数会按 `Double` 取近似值（`Double` 本来就装不下）；`Int` 字段超出 ±2^31 由标准库报 overflow，库翻成「超出 Int 范围」。

`Bytes` 是同一个道理：标准库的 `ToJson for Bytes` 把可打印 ASCII 原样输出、其余写成 `\xHH`，而 `FromJson for Bytes` 读的就是同一套格式（`moonbitlang/core/json/from_json.mbt:309`）。两头都是标准库的实现，不用库自己写编码器，也不会和标准库走偏。

## 2. 错误消息

`derive(FromJson)` 抛的是 `JsonDecodeError((JsonPath, String))`，`JsonPath` 的 `Show` 是 JSON Pointer（`/db/port`）。`extract` 拿这个路径反查 `Value`，翻成和 `get_*` 同一套错误：

| 情况 | 错误 |
|---|---|
| 字段缺失（`Missing field port`） | `MissingKey("db.port")` |
| 类型不符（`Int::from_json: expected number`） | `TypeMismatch("db.port", "Int", "Str")` |
| 整数溢出（`Int::from_json: overflow`） | `ParseError("配置项 db.port 超出 Int 范围")` |
| 结构体写了 `Int64`（`expected number in string representation`） | `ParseError("配置项 db.port 是 64 位整数：结构体字段请声明为 Int64Text，或改用 get_int")` |

期望类型从标准库的消息前缀取（`String` → `Str`，`Double` → `Float`，`Map` → `Table`），实际类型从 `Value` 反查，所以消息里的名字和 `get_*` 一致。
