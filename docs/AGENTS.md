# docs 指南

`docs/` 放项目的说明文档。代码怎么写见根目录 `AGENTS.md`；写作与审查规则见
`write-docs` skill。

## 目录

- `AGENTS.md` —— 本文件：文档放在哪、索引
- `design/` —— 设计文档，讲「为什么这样定」
  - [`design.md`](design/design.md) —— 主线与核心数据模型
  - [`sources.md`](design/sources.md) —— Source / Format 接口、core 边界、package 划分、来源追踪、第三方解析器的取舍
  - [`extract.md`](design/extract.md) —— 提取到结构体、整数映射、错误消息
  - [`validate.md`](design/validate.md) —— 校验：按键规则表、结构体 `Validate`、未知键、错误
- `decisions/` —— 决策记录，讲「当时为什么这么定」
  - [`decisions.md`](decisions/decisions.md) —— 包名、跨包方法、Bytes、JSON 数值、CBOR 选型、来源追踪（`OriginSite` / `KeyPath`）与合并规则、外部 Source、字符串比较、校验
- `plan/` —— 计划文档，讲「接下来做什么」
  - [`roadmap.md`](plan/roadmap.md) —— 待实现的方向、进度
- `conventions/` —— 项目规范，讲「怎么做」
  - [`testing.md`](conventions/testing.md) —— 测试写法

## 规则

- 一份设计一个文件，按主题命名；决策记录写在 `decisions/`。
- 用户怎么用写在 `README.mbt.md` / `README_EN.md`。
- 新增文档后在本文件的目录里登记。
