# moonfig 最小设计

主线是「多来源 → 统一表示 → 分层合并 → 取值 / 提取到结构体」，先做能跑通的最小闭环。

---

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

---

## 2. 示例用法（仅作参考）

**以下代码只用来表达使用手感，具体 API 名以实现为准。**

示例假定用户包的 `moon.pkg` 长这样：

```
import {
  "MuVirus/moonfig/core" @config,
}

using @config { type Config, type JsonSource, type MemorySource, extract }
```

`using` 把名字提到当前作用域，所以下文写 `Config::new()`、`JsonSource::from_str(...)`，不带 `@config.` 前缀。（若要保留前缀，删掉 `using` 行即可。）

### 2.1 最小：一个 JSON 文本

```moonbit
let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"host\":\"localhost\",\"port\":5432}}"))
  .build()

let host : String = cfg.get_string("db.host")   // "localhost"
let port : Int64 = cfg.get_int("db.port")       // 5432
```

### 2.2 分层覆盖：默认值 → 覆盖值

```moonbit
let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"host\":\"localhost\",\"port\":5432},\"debug\":false}"))
  .add(JsonSource::from_str("{\"db\":{\"port\":6543}}"))
  .build()

cfg.get_string("db.host")   // "localhost"   ← 第一个来源提供，未被覆盖
cfg.get_int("db.port")      // 6543          ← 第二个来源赢
cfg.get_bool("debug")       // false
```

后 `add` 的赢；`db` 表逐 key 合并，不是整张替换。

### 2.3 提取到结构体

```moonbit
struct DbCfg {
  host : String
  port : Int
} derive(FromJson)

let db : DbCfg = extract(cfg.get_value("db"))
println(db.host)   // "localhost"
```

`DbCfg` 用编译器自带的 `derive(FromJson)`。结构体里的 64 位字段写 `Int64Text`（见 §7），
因为 core 的 `FromJson for Int64` 只吃 JSON 字符串，和本库的整数映射对不上。

### 2.4 出错时

```moonbit
// 键不存在
let missing = try { cfg.get_string("db.user") } catch {
  MissingKey(path) => "缺少 \{path}"
  e => e.to_string()
}

// 类型不对
let wrong = try { cfg.get_int("db.host") } catch {
  TypeMismatch(path, expected, actual) =>
    "\{path}: 期望 \{expected}，实际 \{actual}"
  e => e.to_string()
}
```

`missing` 得到 `"缺少 db.user"`；`wrong` 得到类似 `"db.host: 期望 Int，实际 Str"`。

---

## 3. 合并

```moonbit
fn merge(base : Value, over : Value) -> Value
```

三条规则：

- 都是 `Table` → 递归逐 key 合并
- 其它 → `over` 覆盖 `base`
- 数组**整体替换**，不拼接

---

## 4. 来源

```moonbit
pub(open) trait Source {
  fn collect(Self) -> Value raise ConfigError
}
```

只有这几个实现：

- `MemorySource` —— 直接塞一棵 `Table`，用来测合并
- `JsonSource` —— 文本 → `Json` → `Value`（用 core 的 `@json`，零第三方依赖）
- `IniSource` —— INI 文本 → `Value`（自写解析器，零第三方依赖）
- `DotenvSource` —— `.env` 文本 → `Value`（自写解析器，零第三方依赖）
- `YamlSource` —— YAML 文本 → `Value`（解析用 `moonbit-community/yaml`）
- `TomlSource` —— TOML 文本 → `Value`（解析用 `moonbit-community/toml`）
- `XmlSource` —— XML 文本 → `Value`（解析用 `Milky2018/xml`）
- `CborSource` —— CBOR 字节 → `Value`（解析用 `2515050242/cbor`）

编程式构造一棵表：

```moonbit
let defaults = MemorySource::new(
  Value::table({
    "db": Value::table({
      "host": Value::str("localhost"),
      "port": Value::int(5432),
    }),
    "debug": Value::bool(false),
  }),
)
```

---

## 5. 配置对象与取值

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

---

## 6. 错误

```moonbit
pub suberror ConfigError {
  MissingKey(String)                      // 路径没被任何来源提供
  TypeMismatch(String, String, String)    // 路径、想要、实际
  ParseError(String)                      // 文本解析失败（包住 @json.JsonDecodeError）
  MergeConflict(String, String, String)   // 类型冲突：路径、两侧类型
}
```

唯一体验标准：用户看到错误，能立刻知道**哪个键、期望什么、实际什么**。

---

## 7. 提取到结构体

```moonbit
pub fn[T : FromJson] extract(v : Value) -> T raise ConfigError
```

实现是 `@json.from_json(to_json(v))`，但整数映射有一个绕不过去的矛盾：

| 字段类型 | core 的 `from_json` 只认 |
|---|---|
| `Int` / `Int32` | `Json::Number`（±2^31 范围检查） |
| `Int64` / `UInt64` | `Json::String`（只吃字符串） |

`extract[T : FromJson]` 只有值级约束，看不到字段类型，所以一棵 Json 树不可能同时满足两者。取舍是：**统一映射成数字**，64 位字段用包装类型。

| ValueKind | → Json |
|---|---|
| `Int` | `Json::number(i.to_double(), repr=i.to_string())` |
| `Float` | `Json::number` |
| `Bool` | `Json::bool` |
| `Str` | `Json::string` |
| `Bytes` | `Json::string(...)`，走 core 的字节编码 |
| `Null` | `Json::null` |
| `Array` / `Table` | 递归 |

`repr` 是 core 自己的字段：`Json::stringify` 优先写它，所以 `to_json(Value::int(9007199254740993L)).stringify()` 仍是原文 `9007199254740993`，不经过 `Double` 丢精度。`Int64Text` / `UInt64Text` 也读它，结构体里的 64 位字段写 `id : Int64Text`，`to_int64()` 取回原值。

代价：`Double` 字段收到超出 2^53 的整数会按 `Double` 取近似值（`Double` 本来就装不下）；`Int` 字段超出 ±2^31 由 core 报 overflow，库翻成「超出 Int 范围」。

`Bytes` 是同一个道理：core 的 `ToJson for Bytes` 把可打印 ASCII 原样输出、其余写成 `\xHH`，而 `FromJson for Bytes` 读的就是同一套格式（`moonbitlang/core/json/from_json.mbt:309`）。两头都是 core 的实现，不用库自己写编码器，也不会和 core 走偏。

### 7.1 错误消息

`derive(FromJson)` 抛的是 `JsonDecodeError((JsonPath, String))`，`JsonPath` 的 `Show` 是 JSON Pointer（`/db/port`）。`extract` 拿这个路径反查 `Value`，翻成和 `get_*` 同一套错误：

| 情况 | 错误 |
|---|---|
| 字段缺失（`Missing field port`） | `MissingKey("db.port")` |
| 类型不符（`Int::from_json: expected number`） | `TypeMismatch("db.port", "Int", "Str")` |
| 整数溢出（`Int::from_json: overflow`） | `ParseError("配置项 db.port 超出 Int 范围")` |
| 结构体写了 `Int64`（`expected number in string representation`） | `ParseError("配置项 db.port 是 64 位整数：结构体字段请声明为 Int64Text，或改用 get_int")` |

期望类型从 core 的消息前缀取（`String` → `Str`，`Double` → `Float`，`Map` → `Table`），实际类型从 `Value` 反查，所以消息里的名字和 `get_*` 一致。

---

## 8. 文件与推进顺序

```
核心包 MuVirus/moonfig/core —— 只依赖 moonbitlang/core/debug
core/value.mbt    ValueKind + Value + 构造器
core/path.mbt     点号路径取值
core/merge.mbt    merge + 优先级
core/error.mbt    ConfigError
core/source.mbt   Source trait（核心唯一的扩展点）
core/memory.mbt   MemorySource
core/config.mbt   Config 构建器 + get_string / get_int / get_bool / get_float

来源包（各自 import 核心，按需加依赖）
core/source/json_source/   JsonSource + to_json + extract + Int64Text / UInt64Text
core/source/ini_source/    IniSource（自写解析器，无第三方依赖）
core/source/dotenv_source/ DotenvSource（自写解析器，无第三方依赖）
core/source/yaml_source/   YamlSource（依赖 moonbit-community/yaml）
core/source/toml_source/   TomlSource（依赖 moonbit-community/toml）
core/source/xml_source/    XmlSource（依赖 Milky2018/xml）
core/source/cbor_source/   CborSource（依赖 2515050242/cbor）
core/source/env_source/    EnvSource      ← @env 按 target 分文件
core/source/file_source/   FileSource     ← 自写 FFI，按 target 分文件
```

拆包的判据只有一条：**这个模块会不会给核心带来依赖或平台约束。**
`env_source` / `file_source` / `toml_source` 都会，所以必须拆；`json_source` 只依赖 core 的 `@json`，
拆是为了让"只用内存来源"的用户不被 JSON 的依赖链绑住。

`validate` / `autodetect` / `hotreload` 不实现 `Source`，不进 `core/`，放在模块根目录。

> **2026-09 实测：包名不能和 core 包重名，换别名也救不回来。**
> 来源包原本叫 `json/`，后来挪进 `core/source/` 时又试过叫 `json/`，两次都失败。
> 包名本身占一个全局名字：自己的包叫 `json`，`moonbitlang/core/json` 就根本加载不进来
> （`Package "json" not found in the loaded packages`），它的 `.mbti` 里 `@json.JsonPath`
> 这类自引用随之失效。把 core 那边的 import 写成 `@corejson` 也没用——冲突发生在包名，
> 不在别名上。结论：格式包一律保留 `_source` 后缀，`toml_source`、`env_source` 同理
> （`env` 会和 `moonbitlang/core/env` 撞，`file` 迟早也会撞上什么）。

> **2026-09 实测：方法不能跨包。**
> 跨包给别的包的类型加方法会报 `4059: Cannot define method for foreign type`。
> 所以 `Value::to_json` → `to_json(v)`，`Config::extract` → `extract_from(cfg, path)`。
> 自由函数不受影响（`extract(v)` 本来就是自由函数）。设计新 API 时要提前想清楚
> 哪些函数将来可能需要跨包——**能用自由函数就别用方法**。

> **2026-10 决定：`Value` 加 `Bytes` 分支。**
> CBOR 是第一个会产出字节串的格式，而 `Value` 原来没有放字节串的地方。
> 加分支的机械成本很低：全库只有两处对 `ValueKind` 做穷尽匹配
> （`ValueKind::name` 和 `to_json`），`merge` / `get_path` / 各个 `get_*`
> 都只匹配自己关心的形状，不用改。加了之后 `Value` 才真的覆盖了所有格式的取值，
> 「提取到结构体」这条主线也不断——结构体里的 `Bytes` 字段能原样提取出来。

| 步 | 内容 | 验收 |
|---|---|---|
| 1 | `value.mbt` + `error.mbt` | 构造几个 `Value`，`debug_inspect` 形状对 |
| 2 | `merge.mbt` | 嵌套 `Table` 验证「后覆盖前、表逐 key 合、数组整体换」 |
| 3 | `source.mbt` + `config.mbt` | 两个 `MemorySource` 合起来，`get_*` 取到值；缺 key 报 `MissingKey` |
| 4 | `core/source/json_source/` | `Json` 文本 → `Value`，`Int` / `Float` 按有无小数点分开 |
| 5 | `extract` | 大整数端到端不丢 |

第 1~3 步做完，库就能用了（只是来源只有内存）。第 4、5 步各是独立的增量。

---

## 9. 已实测的坑

| 实测 | 结果 | 影响 |
|---|---|---|
| `@json.parse("9007199254740993")` | `Number(9007199254740992, repr=Some(9007199254740993))` | 超出精确整数范围时 `repr` 留着原文，靠它还原大整数 |
| `@json.parse("30")` / `@json.parse("1.5")` | `repr` 都是 `None` | **常见情况拿不到原文**，按有无小数点分的写法不成立 |
| `@json.from_json(@json.parse("\"1.5\""))` 到 `Double` | 失败 `Double::from_json: expected number` | 字符串自动转数字在 Json 层做不到 |
| `@json.from_json(@json.parse("\"true\""))` 到 `Bool` | 失败 `Bool::from_json: expected boolean` | 同上 |
| `@json.from_json(@json.parse("5432.7"))` 到 `Int` | 成功，得 `5432` | **静默截断**，不报错 |

`Json` 的 `Number` 按有无小数分开处理成 `Int` / `Float` 时，`repr` 字段可用来还原大整数。

> **2026-09 更正（实现时实测）**
>
> 上面第 1 行的结论只在「字面量超出 `Double` 精确整数范围（> 2^53 - 1）」时成立；
> core 在常见情况（`repr` 为 `None`）已经**不保留原文**了。所以 `convert.mbt` 改成：
>
> - `repr` 有值 → 原文在手，按 `Int64` 精确解析（`@bigint`）
> - `repr` 是 `None` → 只能看值：整数值且塞得进 `Int64` 就算整数，其余算浮点
>
> 代价：`1.0`、`1e2` 这种写了小数点／指数的整数值也按整数算。
> 反过来不会错——`5432` 一定是整数，不然 `get_int` 全都取不到。
