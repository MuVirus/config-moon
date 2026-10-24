# 项目 AGENTS.md 指南

这是一个 [MoonBit](https://docs.moonbitlang.com) 项目。

你可以在这里浏览和安装额外的 skill：
<https://github.com/moonbitlang/skills>

## 这个项目是什么

`moonfig` 是一个 MoonBit 配置库。它接受来自多个来源的配置（JSON、INI、`.env`、YAML、TOML、
XML、CBOR 以及内存中的表），把每个来源归一成同一种中间表示，再按层合并（后加入的来源覆盖
先加入的），最后按键读取，或提取到用户定义的结构体：

```
多个来源  →  一种中间表示  →  按层合并
          →  按键取值 / 提取到结构体
```

### 设计约束

以下约束适用于本仓库的全部代码：

- **整数精度。** 整数一律存为 `Int64`，不使用浮点数。
- **core 无平台依赖。** core 不含平台相关代码，必须在所有 target 上编译通过；
  文件、环境变量和命令行来源各自一个包，放在模块根目录。
- **结构体提取。** 提取使用 MoonBit 原生的 `derive(FromJson)`；MoonBit 暂不支持派生第三方 trait，
  也不支持宏定义。
- **错误消息。** 每条消息写出键名、期望类型和实际类型。
- **包布局。** `core/` 加上 `core/format/` 下一种格式一个包，再加模块根目录的
  `file_source/`、`env_source/`、`cli_source/`；import 别名一律显式写出
  （`@config`、`@jsonfmt`）。
- **包名。** 包名不得与 core 中的包重名；格式包保留 `_format` 后缀，来源包保留 `_source` 后缀。
- **跨包辅助函数。** 方法不能跨包（`4059`）；改用自由函数，如 `to_json(v)`。

### 文档

文档放在 `docs/`。放在哪、写什么，见 [`docs/AGENTS.md`](docs/AGENTS.md)。

## 项目结构

- MoonBit 的包按目录组织；每个目录有一个 `moon.pkg`，列出这个包的依赖。每个包有自己的源文件、
  黑盒测试文件（后缀 `_test.mbt`）和白盒测试文件（后缀 `_wbtest.mbt`）。

- 顶层目录有一个 `moon.mod`，记录模块元信息。

- 核心包在 `core/`，格式包在 `core/format/`（一种格式一个目录），文件、环境变量和命令行来源在
  模块根目录的 `file_source/`、`env_source/`、`cli_source/`。文档放在 `docs/`，
  见 [`docs/AGENTS.md`](docs/AGENTS.md)。

- 测试遵循 `docs/conventions/testing.md`：公开 API 的示例写在 `///` 文档注释的 ` ```mbt check ` 代码块里，
  私有逻辑放进 `_wbtest.mbt`，公开 API 的行为放进 `_test.mbt`。本项目不用内联测试。

- `.githooks/pre-commit` 里有一个 pre-commit 钩子；每个 clone 执行一次
  `git config core.hooksPath .githooks` 即可启用。

## 编码约定

- MoonBit 的代码按 block 组织，每个 block 用 `///|` 分隔，block 之间的顺序无关紧要。
  有些重构可以按 block 逐个处理。

- 尽量把废弃的 block 放在每个目录下名为 `deprecated.mbt` 的文件里。

## 工具

- `moon fmt` 用来把代码格式化。

- `moon ide` 提供项目导航功能，比如 `peek-def`、`outline` 和 `find-references`。
  详见 $moonbit-agent-guide。

- `moon info` 用来更新包生成的接口，每个包都有一个生成的接口文件 `.mbti`，它是这个包的简要形式化描述。
  如果 `.mbti` 没有变化，说明你的改动对外部使用者没有可见的变化，这通常是安全的重构。

- 最后一步跑 `moon info && moon fmt`，更新接口并格式化代码。检查 `.mbti` 文件的 diff，
  看这些变化是否符合预期。

- 跑 `moon test` 检查测试是否通过。MoonBit 支持快照测试；当输出发生变化时，跑 `moon test --update`
  刷新快照。

- 对稳定或极不可能变化的结果，优先用 `assert_eq` 或 `assert_true(pattern is Pattern(...))`。
  对会记录结构化调试输出的快照测试，derive `Debug` 并用 `debug_inspect`，而不是 derive `Show`。
  对结果确凿、有明确定义的东西（比如科学计算），优先写断言测试。可以用
  `moon coverage analyze > uncovered.log` 看哪些代码没被测试覆盖。
