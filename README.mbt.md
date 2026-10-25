**中文** | [English](README_EN.md)

# moonfig

MoonBit 原生配置库

**一处声明，多来源汇入。**

## 目录

- [功能特性](#功能特性)
- [快速开始](#快速开始)
- [示例](#示例)
- [开发路线图](#开发路线图)
- [文档](#文档)
- [许可证](#许可证)

---

## 功能特性

- **类型安全配置**：通过 `derive(FromJson)` 自动生成配置结构体的反序列化实现，提取结果即为该类型；无需额外的代码生成器，使用 MoonBit 原生派生机制
- **严格类型转换**：取值与提取都按声明的类型逐项检查，不做隐式转换，类型不服即错误
- **多格式支持**：JSON、INI、dotenv、YAML、TOML、XML、CBOR 字节或自建的 `Value` 树都能作为来源，换格式不用改上层声明
- **自动发现格式**：`Detector` 先认文件后缀，再看内容；无法判断时报 `UnknownFormat` 并列出候选后缀
- **热更新**：`build_live()` 保留来源清单，`Watcher::poll()` 检测文件变化并替换快照；坏配置不会生效
- **多层来源**：内存默认值、配置文件、环境变量、命令行参数按加入顺序叠加，后加的覆盖先加的
- **按键合并**：后加入的来源只覆盖先加入来源的同名键，同名之外的键全部保留
- **错误信息明确**：`MissingKey` / `TypeMismatch` / `ParseError` / `UnknownFormat`，错误消息包含键名、期望类型与实际类型
- **来源可追**：`origin_of` / `origins()` 给出源对象和结构化层级路径，展示用的 label 按需生成
- **可校验**：按键用规则表，结构体用 `Validate`，启动时一次暴露缺失、越界和未知键

---

## 快速开始

在 `moon.pkg` 中加入依赖：

```moonbit
import {
  "MuVirus/moonfig/core" @config,
  "MuVirus/moonfig/core/format/json_format" @jsonfmt,
}
```

> **别名显式写出来。** 省略别名时 MoonBit 按目录名绑定，核心会变成 `@core`，实测能编译；
> 本项目统一写 `@config` / `@jsonfmt`，短，且目录再调整时用户的写法不用跟着改。

核心包 `core/` 提供 `MemorySource`、`StringSource`、`BytesSource`：内存里的 `Value` 树、
一段文本、一段字节。其余格式各占一个包，名字是 `core/format/<格式>_format`，
只提供 `XxxFormat`；把需要的包写进 `moon.pkg`，再和 `StringSource` / `BytesSource` 组合。
映射规则在每个包的文档注释里。文件、环境变量和命令行来源在模块根目录的
`file_source/`、`env_source/`、`cli_source/`，用法见[下文](#文件环境变量命令行)。

叠加两个来源，后加入的覆盖先加入的：

```moonbit nocheck
using @config { type Config, type StringSource }
using @jsonfmt { type JsonFormat }

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"host\":\"localhost\",\"port\":5432}}", JsonFormat::new()))
  .add(StringSource::new("{\"db\":{\"port\":6543}}", JsonFormat::new()))
  .build()

cfg.get_string("db.host")   // "localhost"   ← 第一个来源提供，未被覆盖
cfg.get_int("db.port")      // 6543          ← 第二个来源覆盖
```

---

## 示例

### 类型安全

取值按实际类型严格匹配，不做隐式转换：

```moonbit nocheck
using @config {type Config, type StringSource}
using @jsonfmt {type JsonFormat, extract_from}

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"port\":\"5432\"}}", JsonFormat::new()))
  .build()

cfg.get_string("db.port")   // "5432"
cfg.get_int("db.port")      // 报错：配置项 db.port 类型不符：期望 Int，实际 Str

struct TextPort {
  port : String
} derive(FromJson)

struct NumericPort {
  port : Int
} derive(FromJson)

let text : TextPort = extract_from(cfg, "db")       // port = "5432"
let numeric : NumericPort = extract_from(cfg, "db") // 报错：期望数字，实际字符串
```

### 按键取值

`MemorySource` 装默认值，按声明的类型取值；形状不符就报错，不做转换：

```moonbit nocheck
using @config {type Config, type MemorySource, type Value}

let cfg = Config::new()
  .add(
    MemorySource::new(
      Value::table({
        "db": Value::table({ "host": Value::str("localhost"), "port": Value::int(5432L) }),
        "debug": Value::bool(false),
        "ratio": Value::float(0.5),
      }),
    ),
  )
  .build()

cfg.get_string("db.host")   // "localhost"
cfg.get_int("db.port")      // 5432
cfg.get_bool("debug")       // false
cfg.get_float("ratio")      // 0.5
```

### 多来源叠加

来源之间不必同一种格式，后加入的只覆盖同名键：

```moonbit nocheck
using @config {type Config, type StringSource}
using @jsonfmt {type JsonFormat}
using @inifmt {type IniFormat}
using @dotenvfmt {type DotenvFormat}

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"host\":\"localhost\",\"port\":5432}}", JsonFormat::new())) // 默认值
  .add(StringSource::new("[db]\nport = 6000\n", IniFormat::new()))                              // 配置文件
  .add(StringSource::new("db.port=6543", DotenvFormat::new()))                                  // 环境覆盖
  .build()

cfg.get_string("db.host")   // "localhost"   只有第一个来源提供
cfg.get_int("db.port")      // 6543          最后加入的赢
```

默认规则是 `LastWins`；要换顺序用 `.with_rule(MergeRule::FirstWins)`，按来源类型排用 `MergeRule::ByKind([...])`，也可以传自定义函数。

### 文件、环境变量、命令行

外部来源各占一个包，和格式包分开：

```moonbit nocheck
import {
  "MuVirus/moonfig/file_source" @file_source,
  "MuVirus/moonfig/env_source" @env_source,
  "MuVirus/moonfig/cli_source" @cli_source,
}
```

```moonbit nocheck
using @config {type Config, type MemorySource, type Value}
using @jsonfmt {type JsonFormat}
using @file_source {type FileSource}
using @env_source {type EnvSource}
using @cli_source {type CliSource}

let cfg = Config::new()
  .add(MemorySource::new(Value::table({ "db": Value::table({ "port": Value::int(5432L) }) })))
  .add(FileSource::new("config/app.json", JsonFormat::new()))  // 读文件，格式自己挑
  .add(EnvSource::new("APP_"))                                  // APP_DB_PORT=6543 → db.port
  .add(CliSource::new())                                        // --log-level=debug → log.level
  .build()
```

- `FileSource`：路径加一个 `Format`，读不到文件报 `IoError`（带路径），解析失败报 `ParseError`；`origin_of` 拿到的 `locator` 能重新读同一个文件。
- `EnvSource`：只读指定前缀的变量，`_` 和 `.` 都算层级，键名转小写，值按字面猜类型（`"5432"` → `Int`、`"true"` → `Bool`）；`EnvSource::all()` 读全部变量。标量占了层级名、或两个变量落到同一个路径时报错，不猜谁该赢。
- `CliSource`：只认 `--key=value`、`--flag`、`--no-flag`，`--` 之后全是位置参数；同一个键写两次后写的赢，标量和层级互相挡路时报错；标签是不带值的参数名，密码不会漏进日志。

### 自动发现格式

不写格式，把路径交给 `FileSource::auto`：

```moonbit nocheck
using @config {type Config}
using @file_source {type FileSource}
using @format_detect {type Detector}
using @jsonfmt {type JsonFormat}
using @tomlfmt {type TomlFormat}
using @yamlfmt {type YamlFormat}

let detector = Detector::new([
  JsonFormat::new(),
  TomlFormat::new(),
  YamlFormat::new(),
])

let cfg = Config::new()
  .add(FileSource::auto("config/app.toml", detector))
  .build()
```

后缀认识就直接用对应格式；后缀缺失或不认识时，按候选顺序看内容，第一个「像」的胜出。候选顺序就是优先级，JSON 应排在 YAML 前面，因为 JSON 通常也是合法 YAML。后缀认识但解析失败时直接报 `ParseError`，不会偷偷换下一个候选；后缀和内容都不像时报 `UnknownFormat`，消息里列出候选后缀。

完整示例：[examples/format_detect](examples/format_detect/README.md)。

### 热更新

`build_live()` 和 `build()` 一样先合并，但保留来源清单：

```moonbit nocheck
using @config {type Config, type Rule}
using @file_source {type FileSource}
using @format_detect {type Detector}
using @jsonfmt {type JsonFormat}
using @hot_reload {type Watcher}

let live = Config::new()
  .add(FileSource::auto("config/app.json", Detector::new([JsonFormat::new()])))
  .build_live()

let watcher = @hot_reload.watch(
  live,
  interval=1000,
  on_change=fn(cfg) { println("port = \{cfg.get_int("db.port")}") },
  on_error=fn(error) { println("新配置没生效：\{error}") },
)

// 由调用方的定时器或事件循环调用；返回 true 表示检测到变化并尝试 reload
watcher.poll()

// 也可以手动重载并带校验规则
live.reload(rules=[Rule::int_range("db.port", 1L, 65535L)])
watcher.stop()
```

`watch()` 只登记回调和 `LiveConfig`，不启动定时器；`interval` 是建议值，实际节奏由调用方决定，这样库不绑定某个异步运行时。`poll()` 只跟踪文件来源，比较内容而不看 mtime；环境变量和命令行没有可靠的变化事件，仍用 `reload()`。解析或校验失败时旧快照继续用，修好后下一次 `poll()` 会自动生效。

完整示例：[examples/hot_reload](examples/hot_reload/README.md)。

### 来源追踪

每个值都记着来自哪一层，取值之后可以直接问：

```moonbit nocheck
using @config {type Config, type MemorySource, type Value}

let cfg = Config::new()
  .add(
    MemorySource::new(
      Value::table({ "db": Value::table({ "port": Value::int(5432L) }) }),
    ),
  )
  .build()

let origin = cfg.origin_of("db.port").unwrap()
origin.kind()           // SourceKind::Memory
origin.label()          // "memory"
origin.path().to_string() // "db.port"
cfg.origins()           // [Origin { ... }]，只列叶子路径
```

`origin.kind()` 可以直接模式匹配；`origin.path()` 给结构化的 `KeyPath`，需要逐段判断时不用拆字符串；
`label()` 只用于展示，按需生成，不反解析。要重新读原始内容时用 `origin.locator()`。
查询在没 `build()` 时会现场合并，所以带 `raise`。

### 提取到结构体

使用编译器自带的 `derive(FromJson)`：

```moonbit nocheck
using @jsonfmt {extract_from}

struct DbCfg {
  host : String
  port : Int
} derive(FromJson)

let db : DbCfg = extract_from(cfg, "db")
```

结构体字段不建议使用 `Int64` / `UInt64`：core 的 `FromJson` 只接受 JSON 字符串，与本库的整数映射不兼容。替代方案是 `Int64Text` / `UInt64Text`，通过 `to_int64()` / `to_uint64()` 取值。

```moonbit nocheck
using @jsonfmt {extract_from, Int64Text}

struct OrderCfg {
  id : Int64Text
} derive(FromJson)

let order : OrderCfg = extract_from(cfg, "order")
order.id.to_int64()   // 9007199254740993，超出 Double 精确范围也不丢
```

### 校验

配置读进来先验一遍，问题在启动时暴露。按键用规则表：

```moonbit nocheck
using @config {type Rule}

cfg.validate([
  Rule::int_range("db.port", 1L, 65535L),
  Rule::one_of("log.level", ["debug", "info", "warn", "error"]),
  Rule::allowed_keys("db", ["host", "port"]),
])
```

提取到结构体后校验，约束写在 `Validate` 实现里：

```moonbit nocheck
using @jsonfmt {extract_validated_from}

impl @config.Validate for DbCfg with fn validate(self, prefix) {
  @config.check_int_range(prefix.add("port"), self.port.to_int64(), 1L, 65535L)
}

let db : DbCfg = extract_validated_from(cfg, "db")
```

`validate` 遇错即停，`validate_all` 一次列全；必填项靠 `MissingKey`，未知键靠 `allowed_keys`（不写就不查）。详见 [validate.md](docs/design/validate.md)。

### 出错时

缺键和类型不符分别报 `MissingKey` / `TypeMismatch`，默认消息带键名、期望类型和实际类型：

```moonbit nocheck
try {
  cfg.get_int("db.host")
} catch {
  e => println(e)
}
```

上面得到 `配置项 db.host 类型不符：期望 Int，实际 Str`；缺键则得到
`配置项 db.user 不存在：没有任何来源提供它`。

`extract_from` 的失败走同一套：字段缺失报 `MissingKey`，类型不符报 `TypeMismatch`，
路径带上配置路径（`db.port`）。

---

## 开发路线图

| 状态 | 方向 | 条目 |
|---|---|---|
| 🚧 | **核心** | 统一的配置值类型、按键合并、按键取值、按结构体取值、错误处理 |
| 🚧 | **多格式** | JSON、INI、dotenv、YAML、TOML、XML、CBOR 七种格式 |
| ✅ | **外部来源** | 配置文件、环境变量、命令行、多个来源任意组合 |
| 🚧 | **来源追踪** | 某个键最终来自哪一层 |
| ✅ | **校验** | 必填项、取值范围、自定义规则 |
| ✅ | **自动发现格式** | 按后缀判断、按内容判断、无法判断时报错 |
| ✅ | **热更新** | 轮询文件变化、重新读取并合并、回调通知、失败时保留旧配置 |

✅ 已完成（进入维护）　🚧 进行中　⬜ 未进行

热更新的定时器由调用方驱动：`Watcher::poll()` 负责一轮检测，`interval` 只是建议值。

完整的条目和取舍见 [docs/plan/roadmap.md](docs/plan/roadmap.md)。

---

## 文档

- `moon doc` —— 生成 API 文档到 `_build/doc/`
- `moon doc --serve` —— 启动本地预览（默认 http://127.0.0.1:3000）
- `examples/` —— 可运行示例，`moon run examples/<示例名>`
- [docs/AGENTS.md](docs/AGENTS.md) —— 文档索引与写作规范
- [docs/design/format-detect.md](docs/design/format-detect.md) —— 自动发现格式的设计
- [docs/design/hot-reload.md](docs/design/hot-reload.md) —— 热更新的设计

---

## 许可证

Apache-2.0
