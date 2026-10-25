# 自动发现格式

目标：调用方只给路径和一组候选格式，库自己决定用哪个解析器。判断错比直接报错更糟，所以规则要可预测。

## 判断顺序

1. **后缀认识 → 用对应格式。** 后缀是调用方的声明，优先级最高；哪怕内容看起来像另一种格式，也按后缀解析。解析失败就报错，不换下一个候选，否则错误里的位置会来自另一个解析器。
2. **后缀没有或不认识 → 按候选顺序看内容。** 第一个 `sniff` 认为「像」的格式胜出。顺序就是优先级，特征强的候选放前面。
3. **都不像 → 报 `UnknownFormat`。** 错误消息列出候选格式声明的后缀，不猜一个解析器硬解析。

同一个后缀被两个候选认领时，`Detector::new` 直接报错。让顺序决定赢家会把配置错误藏起来，等到换候选顺序时才暴露。

## 内容判断的边界

`sniff` 只回答「像不像」，不负责证明「能不能解析」：

- JSON、CBOR、XML 的特征足够强：首个非空白字符，或首字节的 CBOR major type。
- YAML、TOML 只能看行结构，天然会互相重叠；候选顺序决定谁先被问。
- INI 和 `.env` 内容上分不开，只认后缀，不参与内容判断。

用完整解析来判断格式会让「内容坏了」和「格式不对」混在一起，也会把一个候选的语法错误当成另一个候选的失败。`sniff` 保持廉价、保守，真正的错误留给选中的解析器。

## 接口与位置

`Format` 在 `core/` 里提供三样自我介绍：

- `suffixes`：不带点的后缀列表，默认空。
- `sniff`：只看开头，默认 `false`。
- `decode_path`：知道路径时先看后缀，默认直接 `decode`。

[`format_detect/`](../../format_detect/) 提供 `Detector`，负责归一化后缀、检查重复声明、按候选顺序做内容判断。它不读文件，也不依赖平台 API。

候选表由调用方给：core 不能反向 import 格式包，格式包也没有运行时自注册。这样只用 JSON 的项目不必被迫链上 YAML、XML 和 CBOR；需要默认列表时，由应用自己 import 并组装。

[`FileSource::auto`](../../file_source/file_source.mbt) 在 `file_source/` 里把路径和已读出的字节交给 `Detector`；普通 `FileSource::new` 仍然直接使用传入的 `Format`。`StringSource` / `BytesSource` 没有路径，把 `Detector` 当普通 `Format` 用即可，只做内容判断。

## 示例

[examples/format_detect](../../examples/format_detect/README.md) 用 `.toml`、`.yaml` 和后缀不认识的 JSON 文件演示后缀优先与内容回退。

相关：[sources.md](sources.md) 说明 `Format` 与 `Source` 的分工，[roadmap.md](../plan/roadmap.md) 记录实现进度。
