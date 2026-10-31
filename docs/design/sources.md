# Source 与 package 布局

两层接口，各管一件事：

- `Source` 管「从哪读」，产出一层配置和这层的来源（`Layer`）。
- `Format` 管「怎么解析」，把一段字节解成 `Value`。

`Source` 是 `core/` 定义的 trait：

```moonbit
pub(open) trait Source {
  fn collect(Self) -> Layer raise ConfigError
  fn kind(Self) -> SourceKind = _   // 默认 Custom
  fn raw_locator(Self) -> &Locator? = _   // 默认 None；热更新用
}

pub struct Layer {
  value : Value
  origin : &OriginSite?
}
```

`Config::add` 只认 `Source`；默认按加入顺序合并，规则见 [design.md](design.md#3-配置对象与取值)。
`Source::kind` 给 `ByKind` 排序用，不需要先 `collect`。`Source::raw_locator` 给热更新用：
文件来源返回可重读的 `Locator`，即使它的键被后面的来源覆盖，改文件仍然能触发重读；见
[hot-reload.md](hot-reload.md#什么算变化)。

## 六种 Source

- `MemorySource`：程序内已经构造好的 `Value`，用来写默认值、测合并规则。
- `StringSource`：一段文本 + 一个 `Format`。
- `BytesSource`：一段字节 + 一个 `Format`。
- `FileSource`：路径 + 一个 `Format`，自己读文件。
- `EnvSource`：读进程环境变量。
- `CliSource`：读命令行参数。

没有 `JsonSource`、`TomlSource` 这类类型。它们只是「字符串 + 某种格式」，写成 `StringSource` 加 `JsonFormat` 就够了；每种格式再包一个 Source，只会让「格式」和「从哪读」继续混在一起。

`EnvSource`、`CliSource` 不用 `Format`：它们的输入是键值对和 argv，不是一段文本或字节。
它们和 `dotenv_format` 一样要猜类型，但猜法必须跨包共用，所以核心提供 `Value::from_literal`：

```moonbit
pub fn Value::from_literal(StringView) -> Value raise ConfigError
```

`true` / `false` → `Bool`，整数 → `Int64`，带小数点或指数的 → `Float`，其余 → 字符串；
整数超出 `Int64` 报 `ParseError`，不静默降级。类型推断必须在这一层做完，等到按结构体取值时，
标准库的 `Bool::from_json` / `Double::from_json` 都拒收字符串。

`EnvSource` 的规则：只读指定前缀的变量，前缀不参与键名；`_` 和 `.` 都算层级，键名统一转小写；
整层共用一个 site，site 里存「路径 → 变量名」索引，`origin_of("db.port")` 能指出是
`APP_DB_PORT`。标量占了层级名、或两个变量落到同一个路径时报 `ParseError`，不按遍历顺序猜赢家。

`CliSource` 的解析规则（取值风格、短选项、数组、冲突）见 [cli-args.md](cli-args.md)。

## `core/` 里放什么

只放 `Source`、`Format`、`Locator`、`OriginSite` 四个 trait，`MemorySource`、`StringSource`、`BytesSource` 三个实现，以及热更新用的 `LiveConfig`。`LiveConfig` 只通过 `Locator` 读字节，不直接调平台 API；`FileSource`、`EnvSource`、`CliSource` 不额外定义标记 trait，各自在自己包里 `impl Source`；`FileSource` 另外实现 `OriginSite` 和 `Locator`。

`core/` 里这三个实现是纯计算，不碰 IO，所有 target 都能编；每个格式 package 又都要用 `StringSource` / `BytesSource`，放在 `core/` 才不会各写一份。

`FileSource` 读文件、`EnvSource` 读进程环境、`CliSource` 读 argv，都带平台约束；`EnvSource` 还多一整套前缀、分隔符、嵌套键和类型推断的规则。放进 `core/` 就破了「`core/` 无平台代码」。

## package 划分与命名

- `core/`：core 包，四个 trait、三个内存实现，以及 `LiveConfig`。
- `core/format/xxx_format/`：只提供一个 `Format` 类型，例如 `JsonFormat`、`TomlFormat`，不再包一层 `Source`。依赖写在自己的 `moon.pkg` 里，加一种格式只动这个 package。
- `file_source/`、`env_source/`、`cli_source/`：`Source` 实现，和 `core/` 平级。

后缀写清包里提供什么：格式包用 `_format`，Source 包用 `_source`。这样也避开和 MoonBit 标准库的包重名（`env`、`json` 都撞过），原因见 [decisions.md](../decisions/decisions.md#1-包名不能和-moonbit-标准库的包重名)。

## 什么时候用第三方解析器

没有硬性标准。解析器成熟、好用、不引入平台依赖，符合 `core/` 的设计约束，就直接用；没有合适的，或者格式简单、自己写更可控，就自己写。

TOML、YAML、XML、CBOR 用第三方解析器；JSON、INI、`.env` 是自己写的。

## 来源追踪

追踪信息挂在 `Value` 的每个节点上：节点存一个 `&OriginSite?`，不存 label 字符串，也不另建
「路径 → 来源」的表。表被标量覆盖、数组整体替换时不会留下脏数据。

```moonbit
pub(all) enum SourceKind { Memory; File; Env; Cli; Custom }

pub(open) trait OriginSite {
  fn kind(Self) -> SourceKind
  fn describe(Self, KeyPath) -> String
  fn locator(Self) -> &Locator? = _   // 默认 None
}

pub(open) trait Locator {
  fn read(Self) -> Bytes raise ConfigError
}
```

`describe` 拿到 `KeyPath`，所以环境变量、命令行可以按路径查回原始名字；文件来源忽略路径，
只报文件本身。`OriginSite` 是 trait object，`Value` 只多一个引用；label 在查询时生成，不存快照。

`Value` 加一个私有字段 `origin : &OriginSite?`，构造器给 `None`。`Source::collect` 产出
`Layer`，把值和这层的 site 一起交给 `Config`：

```moonbit
pub(open) trait Source {
  fn collect(Self) -> Layer raise ConfigError
  fn kind(Self) -> SourceKind = _   // blanket impl 给 Custom
  fn raw_locator(Self) -> &Locator? = _   // 默认 None；热更新用
}
```

`Format` 不打标——同一个 `JsonFormat` 可能解析内存字符串，也可能解析文件，它不知道位置。
它另外提供 `suffixes` / `sniff` / `decode_path` 三个默认方法，让格式自己声明后缀和内容特征；
自动发现见 [format-detect.md](format-detect.md)。

`Config::merged` 在每次 `collect()` 后递归给整棵树补 site，再 merge；`build` 清掉 `sources`
也不丢信息。合并时 site 跟着赢家走，表节点取覆盖方的 site。已经有 site 的节点不会被覆盖，
组合来源可以先用 `Value::with_origin` 给子树标不同的 site。

### 展示与反推

`label` 只给人看，不解析、不反推。查询返回 `Origin`，它是「site + 路径」：

- `Config::origin_of(path) -> Origin? raise ConfigError`
- `Config::origin_at(path : KeyPath) -> Origin? raise ConfigError`
- `Config::origins() -> Array[Origin] raise ConfigError`，路径在遍历时算出来，不存进节点

`Origin` 的方法：`kind()`、`label()`、`path()`、`locator()`、`site()`。`path()` 给结构化的
`KeyPath`（`segments()` / `to_string()`），需要程序化判断时直接看段，不用拆字符串。

两个查询在没 `build()` 时会现场合并，所以保留 `raise`；路径不存在时 `origin_of` 给 `None`。
`StringSource` / `BytesSource` 报 `SourceKind::Custom`，标签是 `string` / `bytes`。

`FileSource` 自己是这层的 site，同时实现 `Locator`：`label()` 是 `file:<路径>`，
`locator()` 调一次 `read()` 就重新读出同一份字节。它的 `raw_locator()` 也返回自己，
所以热更新能跟踪到被覆盖的文件来源。读文件失败报 `ConfigError::IoError`，
消息里带路径和底层原因；解析失败仍是 `ParseError`。

环境变量、命令行的 site 里存「路径 → 原始变量名/参数名」索引：`describe(path)` 拼成
`env:APP_DB_PORT` / `cli:--log-level`；表节点查不到时退回 `env:前缀*` / `cli:args`。
索引来自这次真正读到的变量或 argv，不是格式化好的 label。

`MemorySource` 用一个独立的空 site，不返回自己：`MemorySource` 持有值树，值树再指回去就是环。
native 默认的引用计数不回收环（`MOONBIT_TRIAL_DELETION=0`），JS / wasm-gc 的 tracing GC 才收。

`&T` 在 MoonBit 里是 trait object，只能用于 trait，不是 Rust 的借用；没有生命周期检查。
所以 `Origin` 可以安全地持有 site，但 `&Path` 不成立（`Path` 是 struct），core 里也不能靠
`&` 引用具体类型。

`FileSource` 的路径就是 `String`，和 `moonbitlang/x/fs` 的接口一致。`@path` 技术上能进 core，
但会带进平台分派；`Path` 也只是 `String` 包装，`@fs` 只收 `String`。需要路径运算时在
`file_source` 包内用 `Path`，core 的 site 仍然是 `String`。

不用 `String?` 当来源：消费端得靠 `starts_with("file:")` 判断，前缀拼错、漏解析都不会报错；
trait object + enum 能穷尽匹配。

`Value` 的 `Eq` 要手写成只比 `kind`，否则内容相同、来源不同的两个值不相等。

一个语义限制：表节点的 site 是「最后碰它的那层」，反推只对叶子准确；要完整历史，就得把
`origin` 从单个 site 变成列表。

## 跨 package 的 API

方法不能跨 package，跨 package 的能力写成自由函数：`to_json(v)`、`extract_from(cfg, path)`。设计新 API 时能用自由函数就别用方法。记录见 [decisions.md](../decisions/decisions.md#2-方法不能跨包)。
