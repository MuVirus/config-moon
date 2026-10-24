# Source 与 package 布局

两层接口，各管一件事：

- `Source` 管「从哪读」，产出一层配置（一棵 `Value`）。
- `Format` 管「怎么解析」，把一段字节解成 `Value`。

`Source` 是 `core/` 定义的 trait：

```moonbit
pub(open) trait Source {
  fn collect(Self) -> Value raise ConfigError
}
```

`Config::add` 只认 `Source`；默认按加入顺序合并，规则见 [design.md](design.md#3-配置对象与取值)。

## 六种 Source

- `MemorySource`：程序内已经构造好的 `Value`，用来写默认值、测合并规则。
- `StringSource`：一段文本 + 一个 `Format`。
- `BytesSource`：一段字节 + 一个 `Format`。
- `FileSource`：路径 + 一个 `Format`，自己读文件。
- `EnvSource`：读进程环境变量。
- `CliSource`：读命令行参数。

没有 `JsonSource`、`TomlSource` 这类类型。它们只是「字符串 + 某种格式」，写成 `StringSource` 加 `JsonFormat` 就够了；每种格式再包一个 Source，只会让「格式」和「从哪读」继续混在一起。

`EnvSource`、`CliSource` 不用 `Format`：它们的输入是键值对和 argv，不是一段文本或字节。

## `core/` 里放什么

只放 `Source`、`Format`、`Locator` 三个 trait，和 `MemorySource`、`StringSource`、`BytesSource` 三个实现。`FileSource`、`EnvSource`、`CliSource` 不额外定义标记 trait，各自在自己包里 `impl Source`，`FileSource` 另外实现 `Locator`。

这三个是纯计算，不碰 IO，所有 target 都能编；每个格式 package 又都要用 `StringSource` / `BytesSource`，放在 `core/` 才不会各写一份。

`FileSource` 读文件、`EnvSource` 读进程环境、`CliSource` 读 argv，都带平台约束；`EnvSource` 还多一整套前缀、分隔符、嵌套键和类型推断的规则。放进 `core/` 就破了「`core/` 无平台代码」。

## package 划分与命名

- `core/`：core 包，三个 trait 加三个实现。
- `core/format/xxx_format/`：只提供一个 `Format` 类型，例如 `JsonFormat`、`TomlFormat`，不再包一层 `Source`。依赖写在自己的 `moon.pkg` 里，加一种格式只动这个 package。
- `file_source/`、`env_source/`、`cli_source/`：`Source` 实现，和 `core/` 平级。

后缀写清包里提供什么：格式包用 `_format`，Source 包用 `_source`。这样也避开和 MoonBit 标准库的包重名（`env`、`json` 都撞过），原因见 [decisions.md](../decisions/decisions.md#1-包名不能和-moonbit-标准库的包重名)。

## 什么时候用第三方解析器

没有硬性标准。解析器成熟、好用、不引入平台依赖，符合 `core/` 的设计约束，就直接用；没有合适的，或者格式简单、自己写更可控，就自己写。

TOML、YAML、XML、CBOR 用第三方解析器；JSON、INI、`.env` 是自己写的。

## 来源追踪

追踪信息挂在 `Value` 的每个节点上，不另建「路径 → 来源」的表；表被标量覆盖、数组整体替换时不会留下脏数据。

```moonbit
pub(all) enum SourceKind { Memory; File; Env; Cli; Custom }

pub(all) struct Origin {
  kind : SourceKind
  label : String        // 只用于展示
  locator : &Locator?   // 能反推时才给
}

pub(open) trait Locator {
  fn read(Self) -> Bytes raise ConfigError
}
```

`Value` 加一个私有字段 `origin : Origin?`，构造器一律给 `None`。`Source` 报自己的来源：

```moonbit
pub(open) trait Source {
  fn collect(Self) -> Value raise ConfigError
  fn origin(Self) -> Origin? { None }
}
```

`Format` 不打标——同一个 `JsonFormat` 可能解析内存字符串，也可能解析文件，它不知道位置。

`Config::merged` 在每次 `collect()` 后递归给整棵树写 origin，再 merge；`build` 清掉 `sources` 也不丢信息。合并时 origin 跟着赢家走，表节点取覆盖方的 origin。

### 展示与反推

`label` 只给人看，不解析、不反推。反推走 `locator`：

- `Config::origin_of(path) -> Origin?`
- `Config::origins() -> Array[(String, Origin)]`，路径在遍历时算出来，不存进节点

`FileSource` 用平台自己的路径或 URL 实现 `Locator`，core 只看到 `read()`。web 上的文件也能反推，core 不需要知道文件系统。

MoonBit 没有 trait object 的 downcast，所以拿不回具体的 `Path` 类型；能做的事必须定义在 `Locator` 上。想直接操作 `Path`，只能把平台类型放进 core 或让 `Value` 泛型化，两者都不做。

`locator` 现在留空：只有 `MemorySource` 时没有可反推的对象。等 `FileSource` 落地再填，接口按真实的平台类型定，而不是先拍一个。

不用 `String?` 当来源：消费端得靠 `starts_with("file:")` 判断，前缀拼错、漏解析都不会报错；enum 能穷尽匹配。

`Value` 的 `Eq` 要手写成只比 `kind`，否则内容相同、来源不同的两个值不相等。

一个语义限制：表节点的 origin 是「最后碰它的那层」，反推只对叶子准确；要完整历史，就得把 origin 从单个变成列表。

## 跨 package 的 API

方法不能跨 package，跨 package 的能力写成自由函数：`to_json(v)`、`extract_from(cfg, path)`。设计新 API 时能用自由函数就别用方法。记录见 [decisions.md](../decisions/decisions.md#2-方法不能跨包)。
