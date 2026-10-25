# 自动发现格式示例

读文件时不用手写格式：`FileSource::auto` 先看后缀，后缀不认识再看内容。这个示例用三种文件演示两条路径：

- `config/app.toml`：后缀 `.toml` 直接决定解析器。
- `config/legacy.yaml`：后缀 `.yaml` 直接决定解析器。
- `config/feature.conf`：后缀不认识，内容看起来像 JSON，所以按内容选中 JSON。

`config/notes.txt` 既没有可用后缀，内容也不像任何候选，用来演示 `UnknownFormat`。

运行：

```sh
moon run examples/format_detect
```

## 候选顺序

```moonbit
let detector = Detector::new([
  JsonFormat::new(),
  TomlFormat::new(),
  YamlFormat::new(),
])
```

后缀认识时，候选顺序不影响结果；只有内容判断时才按这个顺序逐个问，第一个说「像」的胜出。JSON 在 YAML 前面，因为 JSON 文件通常也是合法 YAML，YAML 先问会把 JSON 全认走。

后缀认识但解析失败时不会换下一个候选，而是直接报错。否则错误位置会来自另一个解析器，反而更难查。

## 代码位置

示例入口是 [`main.mbt`](main.mbt)，候选构造和三个文件的读取都在里面。设计取舍见 [`docs/design/format-detect.md`](../../docs/design/format-detect.md)。
