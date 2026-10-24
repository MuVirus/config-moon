# Source 模型收敛

把「从哪读」和「怎么解析」分开。现在七个格式包都叫 `XxxSource`，看起来像七种 Source，其实只是「字符串 + 某种格式」；再加文件和环境变量，语义就混了。

模型本身写在 [sources.md](../design/sources.md)，这里只列要做的事。

## 改什么

- [x] `core/` 只留两个 trait（`Source`、`Format`）和三个实现：`MemorySource`、`StringSource`、`BytesSource`
- [x] 格式包从 `core/source/xxx_source/` 挪到 `core/format/xxx_format/`，公开 API 只留 `Format`：`JsonFormat`、`TomlFormat`、`IniFormat`、`DotenvFormat`、`YamlFormat`、`XmlFormat`、`CborFormat`
- [x] 删掉 `JsonSource` / `TomlSource` / `IniSource` / `DotenvSource` / `YamlSource` / `XmlSource` / `CborSource`，用 `StringSource` / `BytesSource` 加对应 `Format` 代替
- [ ] `FileSource`、`EnvSource`、`CliSource` 放在模块根目录的 `file_source/`、`env_source/`、`cli_source/`，不进 `core/`
- [x] 现有测试改成新写法后全绿，`core/moon.pkg` 仍然只有标准库依赖
- [x] README 的 import 路径和示例跟着改，根目录 `AGENTS.md` / `AGENTS_ZH.md` 的包布局同步

## 顺序

1. ✅ `core/` 加 `Format`、`StringSource`、`BytesSource`，与旧类型并存
2. ✅ 格式包逐个改成 `Format`，目录改名为 `core/format/xxx_format/`，测试跟着改
3. ✅ 删掉七个 `XxxSource`
4. ⬜ 加 `FileSource` / `EnvSource` / `CliSource`
5. ✅ 改 README 的 import 路径和示例

## 验收

- `core/` 的 `moon.pkg` 只有标准库依赖，所有 target 都能编
- 合并、取值、提取、`Value` 的形状不变
- 旧写法的测试全部换成新写法，不留兼容层

## 代价

调用变长，`StringSource::new(text, JsonFormat::new())` 比 `JsonSource::from_str(text)` 啰嗦。缓解办法是给 `Format` 加一个便捷构造，不再多加一个 Source 类型。

Source 追踪不受影响，仍然是在 `Value` 上加 origin。
