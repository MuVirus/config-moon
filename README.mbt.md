<div align="center">

<img src="https://muvirus.github.io/%E9%A1%B9%E7%9B%AE/moonbit/moonfig/logo/moonfig.png" alt="moonbit logo" width="240">

**中文** | [English](README_EN.md)

# moonfig

MoonBit 原生配置库


**一处声明，多来源汇入**

</div>

## 目录

- [项目目标](#项目目标)
- [功能特性](#功能特性)
- [安装](#安装)
- [快速开始](#快速开始)
- [示例](#示例)
- [开发路线图](#开发路线图)
- [文档](#文档)
- [许可证](#许可证)

---

## 项目目标

moonfig 是一个综合性配置库，面向多来源配置：把常见配置格式文件、环境变量和命令行统一成一份配置，按合并规则叠加，再按键或结构体读取。core 部分不依赖平台，全平台可用。

---

## 功能特性

- **类型安全配置**：复用 MoonBit 原生 `derive(FromJson)` 派生机制，支持提取到结构体。本库负责配置值到 Json 的映射和错误翻译，并对容易混淆的类型做额外检查，无需额外的代码生成器。
- **严格类型转换**：取值与提取按声明类型进行检查，对常见的跨类型写法报错，避免隐式转换；唯一的加宽是整数→浮点（`get_float`），需要严格时用 `get_float_strict`。特定类型（如 `BigInt`、`自定义 FromJson` 等）则遵循其自身规则。
- **多格式支持**：JSON、INI、dotenv、YAML、TOML、XML、CBOR 字节或自建的 `Value` 树都能作为来源，换格式不用改上层声明
- **自动发现格式**：`Detector` 先认文件后缀，再看内容；无法判断时报 `UnknownFormat` 并列出候选后缀
- **热更新**：`build_live()` 保留来源清单，`Watcher::poll()` 检测文件变化并替换快照；坏配置不会生效
- **多层来源**：内存默认值、配置文件、环境变量、命令行参数按加入顺序叠加，后加的覆盖先加的
- **按键合并**：后加入的来源只覆盖先加入来源的同名键，同名之外的键全部保留
- **错误信息明确**：`MissingKey` / `TypeMismatch` / `ParseError` / `UnknownFormat`，错误消息包含键名、期望类型与实际类型
- **来源可追**：`origin_of` / `origins()` 按路径反查来源，`snapshot()` 导出路径、值与来源；展示用的 label 按需生成
- **可校验**：按键用规则表，结构体用 `Validate`，启动时一次暴露缺失、越界和未知键

---

## 安装

需要 MoonBit 工具链，安装方法见 [MoonBit 官方文档](https://www.moonbitlang.com/download/)；装好后 `moon version` 应该能输出版本号。

在已有 MoonBit 项目里加依赖：

```sh
moon add MuVirus/moonfig
```

然后在 `moon.pkg` 里按需引入包：

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
`file_source/`、`env_source/`、`cli_source/`，用法见[文件](#文件)、[环境变量](#环境变量)、[命令行参数](#命令行参数)。

从源码运行：

```sh
git clone https://github.com/MuVirus/moonfig.git
cd moonfig
moon update
moon test
moon run examples/multi_source -- --log-level=debug
```

---

## 快速开始

依赖装好后，叠加两个来源，后加入的覆盖先加入的：

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

取值按实际类型匹配，避免隐式转换（浮点数提取到整数字段会报错，不会截断成整数部分；唯一的加宽是整数→浮点，可用 `get_float_strict` 关掉）：

```moonbit nocheck
using @config {type Config, type StringSource}
using @jsonfmt {type JsonFormat, extract_from}

let cfg = Config::new()
  .add(StringSource::new("{\"db\":{\"port\":\"5432\"}}", JsonFormat::new()))
  .build()

cfg.get_string("db.port")   // "5432"
cfg.get_int("db.port")      // 报错：key 'db.port': expected Int, got Str

struct TextPort {
  port : String
} derive(FromJson)

struct NumericPort {
  port : Int
} derive(FromJson)

let text : TextPort = extract_from(cfg, "db")       // port = "5432"
let numeric : NumericPort = extract_from(cfg, "db") // 报错：key 'db.port': expected Int, got Str
```

### 按键取值

`MemorySource` 装默认值，按声明的类型取值；形状不符就报错，除整数→浮点外不做转换：

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

cfg.get_string("db.host")        // "localhost"
cfg.get_int("db.port")           // 5432
cfg.get_bool("debug")            // false
cfg.get_float("ratio")           // 0.5
cfg.get_float("db.port")         // 5432.0，整数按浮点加宽
cfg.get_float_strict("db.port")  // 报错：expected Float, got Int
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

### 文件

`FileSource` 读一个文件，格式由传入的 `Format` 决定：

```moonbit nocheck
import {
  "MuVirus/moonfig/file_source" @file_source,
}

using @config {type Config}
using @file_source {type FileSource}
using @jsonfmt {type JsonFormat}

let cfg = Config::new()
  .add(FileSource::new("config/app.json", JsonFormat::new()))
  .build()
```

读不到文件报 `IoError`（消息带路径），内容解析失败报 `ParseError`；`origin_of` 拿到的 `locator` 能重新读同一个文件。不想指定格式就用 [`FileSource::auto`](#自动发现格式)。

### 环境变量

`EnvSource` 按前缀读环境变量，前缀不参与键名：

```moonbit nocheck
import {
  "MuVirus/moonfig/env_source" @env_source,
}

using @config {type Config}
using @env_source {type EnvSource}

let cfg = Config::new()
  .add(EnvSource::new("APP_"))  // APP_DB_PORT=6543 → db.port
  .build()
```

`_` 和 `.` 都算层级，键名转小写，值按字面猜类型（`"5432"` → `Int`、`"true"` → `Bool`）；`EnvSource::all()` 读全部变量。标量占了层级名、或两个变量落到同一个路径时报错，不猜谁该赢。

### 命令行参数

`CliSource` 读 argv。取值风格二选一，不混用：

```moonbit nocheck
import {
  "MuVirus/moonfig/cli_source" @cli_source,
}

using @config {type Config}
using @cli_source {type CliSource, type CliValueStyle}

let cfg = Config::new()
  .add(
    CliSource::new()
      .with_value_style(CliValueStyle::Separate)  // --start 0
      .with_positional(0, "command")              // simulate
      .with_positional(1, "model")                // model.fmu
      .with_array("tag")                          // --tag a --tag b → ["a", "b"]
      .with_short_option("p", "db.port"),         // -p 5432
  )
  .build()
```

- 默认 `CliValueStyle::Equals` 只认 `--key=value`；`Separate` 只认 `--key value`。另一种写法报错，不静默忽略（`Equals` 下的 `--key value` 只是开关加位置参数）。
- 裸 `--key` 是布尔 `true`，`--no-key` 是 `false`；短选项要先登记，取值写法跟着风格走（`-p=5432` 或 `-p 5432`），布尔短选项可连写 `-vq`。
- `.with_array("tag")` 声明的路径写几次就收成数组；`.with_positional(0, "command")` 把第 0 个位置参数映射到键。
- 没声明成数组的重复键后写的赢；标量和层级互相挡路时报错。
- `--` 之后全是位置参数；没映射的位置参数和没登记的短选项忽略。标签不带值，密码不会漏进日志。

三个来源都是 `Source`，按 `.add` 的顺序叠加，后加的赢；合并规则见[多来源叠加](#多来源叠加)。

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
cfg.snapshot()          // [Entry { ... }]，路径、值、来源一起导出
```

`origin.kind()` 可以直接模式匹配；`origin.path()` 给结构化的 `KeyPath`，需要逐段判断时不用拆字符串；
`label()` 只用于展示，按需生成，不反解析。要重新读原始内容时用 `origin.locator()`。
查询在没 `build()` 时会现场合并，所以带 `raise`。

`snapshot()` 每条给 `path()` / `value()` / `origin()`；表节点递归、数组当叶子，和 `origins()` 同一套口径。
来源未追踪时 `origin()` 是 `None`，不会伪造一个 label。

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

上面得到 `key 'db.host': expected Int, got Str`；缺键则得到
`missing key 'db.user': no source provides it`。

`extract_from` 的失败走同一套：字段缺失报 `MissingKey`，类型不符报 `TypeMismatch`，
路径带上配置路径（`db.port`）。

---

## 开发路线图

| 状态 | 方向 | 条目 |
|---|---|---|
| 🚧 | **核心** | 统一的配置值类型、按键合并、按键取值、按结构体取值、错误处理... |
| ✅ | **多格式** | JSON、INI、dotenv、YAML、TOML、XML、CBOR 七种格式 |
| ✅ | **外部来源** | 配置文件、环境变量、命令行、多个来源任意组合 |
| ✅ | **来源追踪** | 某个键最终来自哪一层 |
| ✅ | **校验** | 必填项、取值范围、自定义规则 |
| ✅ | **自动发现格式** | 按后缀判断、按内容判断、无法判断时报错 |
| ✅ | **热更新** | 轮询文件变化、重新读取并合并、回调通知、失败时保留旧配置 |
| ⬜ | **远程配置支持** | 支持通过 HTTP/URL 在线拉取配置文件，支持超时重试与本地兜底。 |
| ⬜ | **加密存储** | 支持敏感配置字段的加密解析与安全存储。 |

✅ 已完成（进入维护）　🚧 进行中　⬜ 未进行

完整的条目和取舍见 [docs/plan/roadmap.md](docs/plan/roadmap.md)。

---

## 文档

- `moon doc` —— 生成 API 文档到 `_build/doc/`
- `moon doc --serve` —— 启动本地预览（默认 http://127.0.0.1:3000）
- [`examples/`](examples/README.md) —— 5 个可运行示例，索引里列了各自的运行命令
- `moon coverage analyze -- -f summary` —— 跑测试并打印覆盖率摘要
- [docs/AGENTS.md](docs/AGENTS.md) —— 文档索引与写作规范
- [docs/design/cli-args.md](docs/design/cli-args.md) —— 命令行参数的解析设计
- [docs/design/format-detect.md](docs/design/format-detect.md) —— 自动发现格式的设计
- [docs/design/hot-reload.md](docs/design/hot-reload.md) —— 热更新的设计

---

## 许可证

Apache-2.0
