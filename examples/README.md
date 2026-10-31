# 示例

每个目录都是一个独立的 MoonBit 可执行包，在仓库根目录运行。首次运行前先拉依赖：

```sh
moon update
```

| 示例 | 展示什么 | 运行 |
|---|---|---|
| [multi_source](multi_source/README.md) | 默认值、文件、环境变量、命令行四层叠加，以及每个值的来源 | `moon run examples/multi_source -- --log-level=debug` |
| [strict_types](strict_types/README.md) | 按键取值和结构体提取都按声明类型严格检查 | `moon run examples/strict_types` |
| [validate](validate/README.md) | 按键规则表、结构体 `Validate`、未知键和自定义规则 | `moon run examples/validate` |
| [format_detect](format_detect/README.md) | 后缀优先、内容兜底的格式发现，以及 `UnknownFormat` | `moon run examples/format_detect` |
| [hot_reload](hot_reload/README.md) | 轮询文件变化、坏配置保留旧快照、修好后继续更新 | `moon run examples/hot_reload` |

所有示例都能直接运行到结束，不依赖交互输入；输出写在各目录的 `README.md` 里，方便对照。
