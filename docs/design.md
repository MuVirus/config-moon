# config-moon 最小设计

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
  "MuVirus/config-moon" @config,
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
  port : Int64
} derive(FromJson)

let db : DbCfg = extract(cfg.get_value("db"))
println(db.host)   // "localhost"
```

`DbCfg` 用编译器自带的 `derive(FromJson)`，库不需要为用户类型写任何东西。

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

只有两个实现：

- `MemorySource` —— 直接塞一棵 `Table`，用来测合并
- `JsonSource` —— 文本 → `Json` → `Value`（用 core 的 `@json`，零第三方依赖）

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

实现只有一句：`@json.from_json(v.to_json())`。

转换规矩（已实测）：

| ValueKind | → Json |
|---|---|
| `Int` | `Json::string(...)`，**不是** `Json::number` |
| `Float` | `Json::number` |
| `Bool` | `Json::bool` |
| `Str` | `Json::string` |
| `Null` | `Json::null` |
| `Array` / `Table` | 递归 |

`Int` 走字符串的根据：core 自己把 `Int64` 序列化成 JSON 字符串（`@json.to_json(9007199254740993L)` → `String(9007199254740993)`），且 `FromJson for Int64` 第一行 `guard json is String(str)`（`/mnt/c/Users/MrVirus/.moon/lib/core/json/from_json.mbt:72-83`）。双向对称，大整数无损。

---

## 8. 明确不做

- 环境变量来源（类型推断逻辑复杂，先不做）
- TOML / YAML 后端
- 日期类型
- 来源追踪
- 数组拼接
- 自定义 `derive` / 代码生成器

列出来是为了**防止实现时顺手多做**。

---

## 9. 文件与推进顺序

```
核心包 MuVirus/config-moon —— 只依赖 moonbitlang/core/debug
value.mbt      ValueKind + Value + 构造器
path.mbt       点号路径取值
merge.mbt      merge + 优先级
error.mbt      ConfigError
source.mbt     Source trait（核心唯一的扩展点）
memory.mbt     MemorySource
config.mbt     Config 构建器 + get_string / get_int / get_bool / get_float

来源包（各自 import 核心，按需加依赖）
json_source/   JsonSource + to_json + extract
env/           EnvSource      ← @env 按 target 分文件
file/          FileSource     ← @fs
toml/          TomlFormat     ← 第三方依赖
```

拆包的判据只有一条：**这个模块会不会给核心带来依赖或平台约束。**
`env` / `file` / `toml` 都会，所以必须拆；`json_source` 只依赖 core 的 `@json`，
拆是为了让"只用内存来源"的用户不被 JSON 的依赖链绑住。

> **2026-09 实测：包名不能和 core 撞车。**
> 来源包原本叫 `json/`，但包名会占一个全局别名，和 `moonbitlang/core/json` 冲突，
> core 的 `json.mbti` 里 `@json.JsonPath` 这类自引用被遮蔽，直接报
> `Package "json" not found in the loaded packages`。给 core 那边改别名也绕不开
> （冲突发生在引用侧），只能把自己的包改名成 `json_source`。

> **2026-09 实测：方法不能跨包。**
> 跨包给别的包的类型加方法会报 `4059: Cannot define method for foreign type`。
> 所以 `Value::to_json` → `to_json(v)`，`Config::extract` → `extract_from(cfg, path)`。
> 自由函数不受影响（`extract(v)` 本来就是自由函数）。设计新 API 时要提前想清楚
> 哪些函数将来可能需要跨包——**能用自由函数就别用方法**。

| 步 | 内容 | 验收 |
|---|---|---|
| 1 | `value.mbt` + `error.mbt` | 构造几个 `Value`，`debug_inspect` 形状对 |
| 2 | `merge.mbt` | 嵌套 `Table` 验证「后覆盖前、表逐 key 合、数组整体换」 |
| 3 | `source.mbt` + `config.mbt` | 两个 `MemorySource` 合起来，`get_*` 取到值；缺 key 报 `MissingKey` |
| 4 | `json_source/` | `Json` 文本 → `Value`，`Int` / `Float` 按有无小数点分开 |
| 5 | `extract` | 大整数端到端不丢 |

第 1~3 步做完，库就能用了（只是来源只有内存）。第 4、5 步各是独立的增量。

---

## 10. 已实测的坑

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
