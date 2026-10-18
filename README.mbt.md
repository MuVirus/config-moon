# config-moon

MoonBit 配置库

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

- **多格式支持**：JSON 文本或自建的 `Value` 树都能作为来源
- **按键合并**：后加入的来源只覆盖先加入来源的同名键，同名之外的键全部保留
- **错误信息明确**：`MissingKey` / `TypeMismatch` / `ParseError`，错误消息包含键名、期望类型与实际类型

---

## 快速开始

在 `moon.pkg` 中加入依赖：

```
import {
  "MuVirus/config-moon" @config,
  "MuVirus/config-moon/json_source" @jsonsrc,
}
```

> **必须显式指定别名。** 模块名为 `MuVirus/config-moon`，默认别名会解析为 `config-moon`，
> 而 `-` 不是合法的 MoonBit 标识符，因此需要显式指定 `@config`。

核心包提供 `MemorySource`（装自建的 `Value` 树），`json_source` 包提供 `JsonSource`（读 JSON 文本）。

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

从配置中提取到已声明的结构体，使用编译器自带的 `derive(FromJson)`，库无需为用户类型生成任何代码：

```moonbit nocheck
///|
using @jsonsrc {extract_from}

///|
struct DbCfg {
  host : String
  port : Int64
} derive(FromJson)

///|
let db : DbCfg = extract_from(cfg, "db")
```

---

## 开发路线图

| 状态 | 方向 | 条目 |
|---|---|---|
| 🚧 | **核心** | 统一的配置值类型、按键合并、按键取值、按结构体取值、错误处理 |
| 🚧 | **多格式** | 常见通用格式、CBOR、支持其他格式接入 |
| ⬜ | **外部来源** | 配置文件、环境变量、多个来源任意组合 |
| ⬜ | **校验** | 必填项、取值范围、自定义规则 |
| ⬜ | **自动发现格式** | 按后缀判断、按内容判断、无法判断时报错 |
| ⬜ | **热更新** | 监听文件变化、重新读取并合并、回调通知、失败时保留旧配置 |

✅ 已完成（进入维护，只修不改）　🚧 进行中　⬜ 未进行

完整的条目和取舍见 [docs/roadmap.md](docs/roadmap.md)。

---

## 文档

- `moon doc --open` —— 生成的 API 文档
- [docs/roadmap.md](docs/roadmap.md) —— 分阶段计划与推进顺序
- [docs/design.md](docs/design.md) —— 类型设计、合并规则、包划分理由、完整示例
- [docs/testing.md](docs/testing.md) —— 测试写法规范

---

## 许可证

Apache-2.0
