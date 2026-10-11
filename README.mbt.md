# config-moon

一个用 MoonBit 写的配置库。

它把**多个来源**的配置（JSON 文本、代码里直接构造的配置……以后可能有更多）读进来，
按加入顺序**合并**（后加入的覆盖先加入的），最后让你**按键取值**，
或者**提取到自己的结构体**。

---

## 目标

做一条能跑通的最小主线：

```
多来源  →  统一表示  →  分层合并  →  取值 / 提取到结构体
```

具体想要达到：

1. **多来源叠加**。默认值、文件、环境变量各占一层，优先级明确，「环境变量压掉文件」是配置库存在的根本理由。
2. **深合并**。两个来源都有 `db` 表时逐 key 合并，而不是整张表替换。
3. **整数不丢精度**。配置里的大整数（雪花 ID、纳秒时间戳）原样带到用户手上。
4. **错误说人话**。看到报错能立刻知道：哪个键、期望什么、实际什么。
5. **核心不碰 I/O**。`Value` 与合并逻辑不依赖文件系统，能在全部 target 上编译。

## 非目标

不做热重载、不做远程源、不做敏感字段加密、不做自定义 `derive`。
清单写在 `docs/design.md` 第 8 节，列出来是为了防止实现时顺手多做。

---

## 结构

模块里有两个包：

```
config-moon/            核心：零 I/O、零第三方依赖，native / wasm / wasm-gc / js 都编得过
  value.mbt             ValueKind、Value 及构造器
  path.mbt              点号路径取值
  merge.mbt             合并规则
  error.mbt             ConfigError
  source.mbt            Source trait —— 核心唯一的扩展点
  memory.mbt            MemorySource
  config.mbt            Config 构建器 + get_string / get_int / get_bool / get_float
config-moon/json_source/  JSON 来源
  json_source.mbt         JsonSource、to_json、extract、extract_from
```

核心包**只依赖 `moonbitlang/core/debug`**，不认识任何具体格式——它只认识 `Source`。
想读 JSON、读文件、读环境变量，都是来源包的事。这样只用内存来源的用户不会
被 JSON 的依赖链绑住，wasm 用户也不会碰到 `fs` / `env` 这类平台相关的东西。

> **为什么子包叫 `json_source` 而不是 `json`。**
> 包名会占用一个全局别名。叫 `json` 会和 `moonbitlang/core/json` 撞车，
> core 自己的 `json.mbti` 里有 `@json.JsonPath` 这样的自引用会被我们遮蔽，
> 编译直接报 `Package "json" not found`。绕不开，只能改名字。

---

## 用法

`moon.pkg`：

```
import {
  "MuVirus/config-moon" @config,
  "MuVirus/config-moon/json_source" @jsonsrc,
}
```

> **别名必须写。** 模块名是 `MuVirus/config-moon`，默认别名会算成 `config-moon`，
> 而 `-` 在 MoonBit 里不是合法标识符。所以这里要显式指定 `@config`。

代码：

```moonbit nocheck
using @config { type Config, type MemorySource, type Value }
using @jsonsrc { type JsonSource }

// 两个来源，后加入的赢
let cfg = Config::new()
  .add(JsonSource::from_str("{\"db\":{\"host\":\"localhost\",\"port\":5432}}"))
  .add(JsonSource::from_str("{\"db\":{\"port\":6543}}"))
  .build()

cfg.get_string("db.host")   // "localhost"   ← 第一个来源提供，未被覆盖
cfg.get_int("db.port")      // 6543          ← 第二个来源赢
```

`MemorySource` 直接塞一棵已经构造好的表，主要用来写默认值或测试合并：

```moonbit nocheck
///|
let defaults = MemorySource::new(
  Value::table({
    "db": Value::table({
      "host": Value::str("localhost"),
      "port": Value::int(5432L),
    }),
    "debug": Value::bool(false),
  }),
)
```

提取到自己的结构体（用编译器自带的 `derive(FromJson)`，库不需要为用户类型写任何东西）：

```moonbit nocheck
///|
struct DbCfg {
  host : String
  port : Int64
} derive(FromJson)

///|
let db : DbCfg = extract_from(cfg, "db") // 也可以写成 extract(cfg.get_value("db"))
```

> `extract_from` 以前是 `cfg.extract("db")`。跨包不能给别的包的类型加方法
> （`4059: Cannot define method for foreign type`），只能降级成自由函数。

出错时错误会指名道姓地告诉你**哪个键、期望什么、实际什么**：

```moonbit nocheck
try {
  cfg.get_int("db.host")
} catch {
  ConfigError::TypeMismatch(path, expected, actual) =>
    "\{path}: 期望 \{expected}，实际 \{actual}"
  e => e.to_string()
}
// => "db.host: 期望 Int，实际 Str"
```

---

## 状态

主线已跑通，26 个测试全绿（`moon test`）：

- 多来源分层合并，后加者优先，表逐 key 合，数组整体换
- `MemorySource` / `JsonSource` 两个来源，分属两个包，可以混着叠
- 按 key 取值（`get_string` / `get_int` / `get_bool` / `get_float`）与提取到用户结构体
- 缺 key 报 `MissingKey`，类型不对报 `TypeMismatch`，坏文本报 `ParseError`
- 整数全程 `Int64`，`9007199254740993` 这类超出 Double 精度的值不丢

尚未做：环境变量来源、TOML 来源、来源追踪。计划见 `docs/roadmap.md`，
设计细节见 `docs/design.md`。

---

## 许可

Apache-2.0
