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
- **按键合并**：后加入的来源只覆盖先加入来源的同名键，同名之外的键全部保留
- **错误信息明确**：`MissingKey` / `TypeMismatch` / `ParseError`，错误消息包含键名、期望类型与实际类型

---

## 快速开始

在 `moon.pkg` 中加入依赖：

```moonbit
import {
  "MuVirus/moonfig/core" @config,
  "MuVirus/moonfig/core/source/json_source" @jsonsrc,
}
```

> **别名显式写出来。** 省略别名时 MoonBit 按目录名绑定，核心会变成 `@core`，实测能编译；
> 本项目统一写 `@config` / `@jsonsrc`，短，且目录再调整时用户的写法不用跟着改。

核心包 `core/` 提供 `MemorySource`（装自建的 `Value` 树）。其余格式各占一个包，
名字是 `core/source/<格式>_source`，要加哪个格式就把哪个包写进 `moon.pkg`。
映射规则在每个包的文档注释里，完整的包清单见 [docs/design.md](docs/design.md)。

叠加两个来源，后加入的覆盖先加入的：

```moonbit nocheck
using @config { type Config }
using @jsonsrc { type JsonSource }

let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"host\":\"localhost\",\"port\":5432}}"))
  .add(JsonSource::from_str("{\"db\":{\"port\":6543}}"))
  .build()

cfg.get_string("db.host")   // "localhost"   ← 第一个来源提供，未被覆盖
cfg.get_int("db.port")      // 6543          ← 第二个来源覆盖
```

---

## 示例

### 类型安全

取值按实际类型严格匹配，不做隐式转换：

```moonbit nocheck
using @config {type Config}
using @jsonsrc {type JsonSource, extract_from}

let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"port\":\"5432\"}}"))
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
using @config {type Config}
using @jsonsrc {type JsonSource}
using @inisrc {type IniSource}
using @dotenvsrc {type DotenvSource}

let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"host\":\"localhost\",\"port\":5432}}")) // 默认值
  .add(IniSource::from_str("[db]\nport = 6000\n"))                              // 配置文件
  .add(DotenvSource::from_str("db.port=6543"))                                  // 环境覆盖
  .build()

cfg.get_string("db.host")   // "localhost"   只有第一个来源提供
cfg.get_int("db.port")      // 6543          最后加入的赢
```

### 提取到结构体

使用编译器自带的 `derive(FromJson)`：

```moonbit nocheck
using @jsonsrc {extract_from}

struct DbCfg {
  host : String
  port : Int
} derive(FromJson)

let db : DbCfg = extract_from(cfg, "db")
```

64 位字段写 `Int64Text`：core 的 `FromJson for Int64` 只接受 JSON 字符串，和本库的整数映射对不上。

```moonbit nocheck
using @jsonsrc {extract_from, Int64Text}

struct OrderCfg {
  id : Int64Text
} derive(FromJson)

let order : OrderCfg = extract_from(cfg, "order")
order.id.to_int64()   // 9007199254740993，超出 Double 精确范围也不丢
```

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
| ⬜ | **外部来源** | 配置文件、环境变量、命令行、多个来源任意组合 |
| ⬜ | **来源追踪** | 某个键最终来自哪一层 |
| ⬜ | **校验** | 必填项、取值范围、自定义规则 |
| ⬜ | **自动发现格式** | 按后缀判断、按内容判断、无法判断时报错 |
| ⬜ | **热更新** | 监听文件变化、重新读取并合并、回调通知、失败时保留旧配置 |

✅ 已完成（进入维护）　🚧 进行中　⬜ 未进行

完整的条目和取舍见 [docs/roadmap.md](docs/roadmap.md)。

---

## 文档

- `moon doc` —— 生成 API 文档到 `_build/doc/`
- `moon doc --serve` —— 启动本地预览（默认 http://127.0.0.1:3000）
- `examples/` —— 可运行示例，`moon run examples/<示例名>`
- [docs/roadmap.md](docs/roadmap.md) —— 分阶段计划与推进顺序
- [docs/design.md](docs/design.md) —— 类型设计、合并规则、包划分理由、完整示例
- [docs/testing.md](docs/testing.md) —— 测试写法规范

---

## 许可证

Apache-2.0
