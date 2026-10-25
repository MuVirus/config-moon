# 自动发现格式

读文件时不用手写格式：`FileSource` 自己看后缀，看不出来再看内容。

```moonbit
let detector = Detector::new([
  JsonFormat::new(),
  TomlFormat::new(),
])

let cfg = Config::new()
  .add(FileSource::auto("app.toml", detector))
  .build()
```

`app.toml` 直接走后缀；没有后缀、或后缀不认识的文件，才按内容猜。

## 哪些 Source 用得上

`StringSource`、`BytesSource`、`FileSource`。

`EnvSource` / `CliSource` 用不上：它们读的是键值对和 argv，值的类型在读取时就定了（`Value::from_literal`），没有「这段字节该交给哪个解析器」的问题。`.env` 文件仍然归 `dotenv_format`，那是文件，不是环境变量。

## 判断规则

先看后缀，再看内容：

1. **后缀认识** → 用对应格式。哪怕内容其实是另一种格式，也按后缀解析；失败就报错，不偷偷换解析器。否则报错的行号来自另一个格式，用户更难看懂。
2. **后缀没有或不认识** → 按 `Detector` 里的顺序逐个做内容判断，第一个认为「像」的胜出。
3. **都不像** → 报 `UnknownFormat`，消息里列出支持的后缀。

顺序有意义。JSON 文件同时是合法 YAML，YAML 排在前面就会把 JSON 全认走；TOML 和 INI 也长得像。所以顺序就是优先级：**特征强的排前面**。

同一个后缀被两个格式认领，`Detector::new` 直接报错，不让顺序决定赢家。

## 内容判断（`sniff`）

`sniff` 只做一件事：看开头，回答「像不像我」，不负责解析成功。

| 格式 | 看什么 |
|---|---|
| JSON | 第一个非空白字符是 `{` 或 `[` |
| CBOR | 首字节的类型是 map |
| YAML | 有顶层 `key:` 或 `- ` 结构 |
| `.env` / INI | 单看内容分不开，不猜，只认后缀 |

为什么不让它直接解析？因为「不像」是正常结果，而解析失败要抛 `ParseError`；用异常做筛选，会把「不是这种格式」和「是这种格式但写错了」混在一起。所以 `sniff` 返回 `Bool`，拿不准就 `false`。

三方解析器也没有现成的判断接口：YAML、TOML、XML、CBOR 都只提供「解析，失败就抛错」的入口。TOML 的 `TomlValue::validate` 检查的是解析后的值（比如数组是否同类型），不是「这段文本是不是 TOML」。所以不能统一靠「试着解析」来检测，何况 YAML 几乎接受任何文本，而且会白解析一遍。

## 格式怎么声明自己

给 core 的 `Format` trait 加两个方法，都有默认实现：

```moonbit
fn suffixes(Self) -> Array[String]   // 认哪些后缀，默认 []
fn sniff(Self, Bytes) -> Bool        // 内容像不像，默认 false
```

现有格式不改一行也能编，只是不参与自动发现。后缀和内容特征写在格式自己家里，调用方不用再抄一份。

## 候选列表从哪来

`Detector` 不认识具体格式；core 也不能反过来 import 格式包（会成环）。MoonBit 又没有运行时反射，格式包没法自注册。所以候选表只能由调用方给，`Detector::new` 的参数就是列表，顺序即优先级。

想省事可以加一个 `all_formats` 包，import 全部格式并导出默认列表。它不进 core：只用 JSON 的项目不该被迫链上 YAML、XML 和 CBOR。

## 接口

```moonbit
StringSource::new(text, detector)          // 只有内容可看
BytesSource::new(bytes, detector)          // 只有内容可看
```

文件用 `FileSource::auto(path, detector)`。`Detector` 本身就是一种 `Format`，所以文本和字节 Source 直接把它传进去；只有文件需要路径，才多一个 `auto`。选定格式之后的读取、解析、来源追踪，和手写 `Format` 一模一样。

## 错误

新增 `ConfigError::UnknownFormat`：

```text
无法判断 app.conf 的格式：后缀不认识，内容也不像任何候选；支持 .json / .toml / .yaml
```

## 放在哪

| 东西 | 位置 | 原因 |
|---|---|---|
| `suffixes` / `sniff` | `core/` 的 `Format` trait | 格式自己声明特征 |
| `Detector` | `format_detect/` | 只依赖 core，不认识具体格式 |
| `FileSource::auto` | `file_source/` | 要用路径，也负责读文件 |
| 默认候选表 | `all_formats/`（可选） | 唯一 import 全部格式的地方 |

## 不做

- 不打分、不投票：顺序固定，结果可复现。
- 后缀错了不按内容改判：静默换格式比报错更难查。
- 不猜编码：一律按 UTF-8 读。
- 不做目录级约定（比如整个目录都按 YAML 读）。

## 验收

- 不写格式也能读 `app.toml` 和无后缀文件。
- 后缀优先；后缀不认识才看内容；都不行时报 `UnknownFormat` 并列出候选。
- 重复后缀在构造 `Detector` 时报错。
- 现有格式不改一行也能编，`moon test` 全绿。
