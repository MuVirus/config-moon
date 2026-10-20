# 项目 AGENTS.md 指南

这是一个 [MoonBit](https://docs.moonbitlang.com) 项目。

你可以在这里浏览和安装额外的 skill：
<https://github.com/moonbitlang/skills>

## 这个项目是什么

`moonfig` 是一个用 MoonBit 写的配置库。它从多个来源读取配置（JSON 文本、内存里的表，以后还会有更多格式），
把它们归一成一种中间表示，按层合并这些来源（后加入的覆盖先加入的），并让用户按键读取值，
或者提取到自己的结构体。

主线是：

```
多个来源  →  一种中间表示  →  按层合并
          →  按键取值 / 提取到结构体
```

动手改代码前值得知道的设计约束：

- 整数保持完整精度。中间表示把整数存成 `Int64`，而不是 double，这样大数值能原样往返。
- 核心（`Value` 和合并逻辑）不碰 I/O，必须在所有 target 上都能编译。文件和环境变量来源属于独立的子包。
- 提取到用户结构体复用编译器自带的 `derive(FromJson)`；这个库不生成代码，也不定义自定义的 derive trait。
- 错误消息必须写出键名、期望类型和实际类型。
- 模块按包拆分：`MuVirus/moonfig/core`（核心）和 `MuVirus/moonfig/core/source/` 下的来源包
  （一种格式一个目录）。省略别名时 MoonBit 按目录名绑定，实测也能编译；
  但本项目一律显式写出别名（`@config`、`@jsonsrc`），目录将来再调整时用户的写法不用跟着改。
- 包名不能和 core 里的包同名，哪怕每条 import 都写了显式别名也不行。包名本身占一个全局名字，
  叫 `json` 的包会让 `moonbitlang/core/json` 根本加载不进来，它自己的自引用也解析不到。
  所以格式包一律保留 `_source` 后缀。
- 方法不能跨包（`4059: Cannot define method for foreign type`）。要给别的包的类型配一个辅助函数，
  只能写成自由函数：`to_json(v)`，而不是 `v.to_json()`。凡是以后可能挪到别的包里去的，都优先写成自由函数。

动手实现任何东西之前先读 `docs/design.md`。`docs/roadmap.md` 列着还要做的方向，每个都标了已完成、
进行中或未进行。`docs/testing.md` 是本项目的测试约定。

目前已实现：核心包（`Value`、路径取值、合并、错误处理、`Config`、`MemorySource`、提取到用户结构体）
和 `core/source/` 下的来源包：JSON（`JsonSource`、`to_json`、`extract_from`）、
INI（`IniSource`，解析器自己写）、`.env`（`DotenvSource`，解析器自己写）、
YAML（`YamlSource`，解析交给 `moonbit-community/yaml`）、
TOML（`TomlSource`，解析交给 `moonbit-community/toml`）与
XML（`XmlSource`，解析交给 `Milky2018/xml`）。

## 项目结构

- MoonBit 的包按目录组织；每个目录有一个 `moon.pkg`，列出这个包的依赖。每个包有自己的源文件、
  黑盒测试文件（后缀 `_test.mbt`）和白盒测试文件（后缀 `_wbtest.mbt`）。

- 顶层目录有一个 `moon.mod`，记录模块元信息。

- 核心包在 `core/`，来源包在 `core/source/`（一种格式一个目录），`docs/` 放设计、路线图和测试三个文档。

- 测试遵循 `docs/testing.md`：公开 API 的示例写在 `///` 文档注释的 ` ```mbt check ` 代码块里，
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
