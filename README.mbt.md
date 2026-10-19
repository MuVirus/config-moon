# moonfig

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

- **类型安全配置**：通过 `derive(FromJson)` 自动生成配置结构体的反序列化实现，提取结果即为该类型；无需额外的代码生成器，使用 MoonBit 原生派生机制
- **多格式支持**：JSON 文本、INI 文本或自建的 `Value` 树都能作为来源
- **按键合并**：后加入的来源只覆盖先加入来源的同名键，同名之外的键全部保留
- **错误信息明确**：`MissingKey` / `TypeMismatch` / `ParseError`，错误消息包含键名、期望类型与实际类型

---

## 快速开始

在 `moon.pkg` 中加入依赖：

```
import {
  "MuVirus/moonfig/core" @config,
  "MuVirus/moonfig/core/source/json_source" @jsonsrc,
}
```

> **别名显式写出来。** 省略别名时 MoonBit 按目录名绑定，核心会变成 `@core`，实测能编译；
> 本项目统一写 `@config` / `@jsonsrc`，短，且目录再调整时用户的写法不用跟着改。

核心包 `core/` 提供 `MemorySource`（装自建的 `Value` 树），`core/source/json_source/` 包提供 `JsonSource`（读 JSON 文本）。

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

- `moon doc` —— 生成 API 文档到 `_build/doc/`
- `moon doc --serve` —— 启动本地预览（默认 http://127.0.0.1:3000）
- [docs/roadmap.md](docs/roadmap.md) —— 分阶段计划与推进顺序
- [docs/design.md](docs/design.md) —— 类型设计、合并规则、包划分理由、完整示例
- [docs/testing.md](docs/testing.md) —— 测试写法规范

---

## 许可证

Apache-2.0
