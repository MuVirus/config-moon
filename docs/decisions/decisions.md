# 决策记录

记录已经踩过并定了结论的事。实测数据写清出处，结论写清代价。

## 1. 包名不能和 MoonBit 标准库的包重名

> **2026-09 实测：包名不能和 MoonBit 标准库的包重名，换别名也救不回来。**
> 格式 package 原本叫 `json/`，后来挪进 `core/source/` 时又试过叫 `json/`，两次都失败。
> 包名本身占一个全局名字：自己的包叫 `json`，`moonbitlang/core/json` 就根本加载不进来
> （`Package "json" not found in the loaded packages`），它的 `.mbti` 里 `@json.JsonPath`
> 这类自引用随之失效。把标准库那边的 import 写成 `@corejson` 也没用——冲突发生在包名，
> 不在别名上。结论：包名一律带后缀，避免撞名（`env` 会和 `moonbitlang/core/env` 撞，
> `file` 迟早也会撞上什么）。后缀写清包里提供什么：格式包 `_format`，Source 包 `_source`。
> 2026-10 格式包改成只提供 `Format` 后，后缀从 `_source` 改成 `_format`，撞名这个结论不变。

## 2. 方法不能跨包

> **2026-09 实测：方法不能跨包。**
> 跨包给别的包的类型加方法会报 `4059: Cannot define method for foreign type`。
> 所以 `Value::to_json` → `to_json(v)`，`Config::extract` → `extract_from(cfg, path)`。
> 自由函数不受影响（`extract(v)` 本来就是自由函数）。设计新 API 时要提前想清楚
> 哪些函数将来可能需要跨包——**能用自由函数就别用方法**。

## 3. `Value` 加 `Bytes` 分支

> **2026-10 决定：`Value` 加 `Bytes` 分支。**
> CBOR 是第一个会产出字节串的格式，而 `Value` 原来没有放字节串的地方。
> 加分支的机械成本很低：全库只有两处对 `ValueKind` 做穷尽匹配
> （`ValueKind::name` 和 `to_json`），`merge` / `get_path` / 各个 `get_*`
> 都只匹配自己关心的形状，不用改。加了之后 `Value` 才真的覆盖了所有格式的取值，
> 「提取到结构体」这条主线也不断——结构体里的 `Bytes` 字段能原样提取出来。

## 4. JSON 数值的边界

| 实测 | 结果 | 影响 |
|---|---|---|
| `@json.parse("9007199254740993")` | `Number(9007199254740992, repr=Some(9007199254740993))` | 超出精确整数范围时 `repr` 留着原文，靠它还原大整数 |
| `@json.parse("30")` / `@json.parse("1.5")`（默认） | `repr` 都是 `None` | 默认不保留原文，无法按写法区分整数和浮点 |
| `@json.parse("1.0", preserve_number_repr=true)` | `Number(1.0, repr=Some("1.0"))` | 打开选项后每个数字都有原文，按写法分流才成立 |
| `@json.from_json(@json.parse("\"1.5\""))` 到 `Double` | 失败 `Double::from_json: expected number` | 字符串自动转数字在 Json 层做不到 |
| `@json.from_json(@json.parse("\"true\""))` 到 `Bool` | 失败 `Bool::from_json: expected boolean` | 同上 |
| `@json.from_json(@json.parse("5432.7"))` 到 `Int` | 标准库成功，得 `5432` | **标准库会静默截断**；`extract` 用 `"NaN"` 探针把它改成 `TypeMismatch` |

> **2026-10 更正：用 `preserve_number_repr=true` 保住每个数字的写法**
>
> 核心库原来只在超出 `Double` 精确范围时才填 `repr`，所以 `1.0`、`1e2`
> 这种「值是整数、写法是浮点」的数字拿不到原文，只能按数值反推成 `Int`。
> 现在 `@json.parse` 支持 `preserve_number_repr=true`，`JsonFormat::decode`
> 直接打开它，所有数字的原文都在 `repr` 里：
>
> - `repr` 是整数形状（没有小数点、没有 `e` / `E`）→ 按 `Int64` 精确解析
> - 其余形状 → `Float`，包括 `1.0`、`1e2`、`-0.0`
> - `repr` 缺失（只可能来自手工构造的 `Json`）→ 按 `Float` 处理
>
> 这样浮点来源不会再混进 `Int` / `Int64Text` 字段，代价是解析时多存
> 每个数字的原文。`5432` 仍然是 `Int`，`get_int` 不受影响。

## 5. CBOR 库的选择

| 实测 | 结果 | 影响 |
|---|---|---|
| registry 上的 CBOR 库 | `mizchi/cbor`（下载量最高）用的是旧的 `moon.mod.json`，当前工具链拒绝安装 | 只能从 `2515050242/cbor`（纯 MoonBit、零传递依赖、完整 RFC 8949）和 `f4ah6o/simple-webauthn/cbor`（同样零依赖，但是子集：不支持半精度/单精度浮点、不支持不定长容器、而且**静默忽略尾随字节**）里选 |

## 6. 来源追踪与合并规则

> **2026-10 定稿：存来源对象，不存 label 字符串**
>
> - `Value.origin` 的类型是 `&OriginSite?`：每个节点只多一个引用，不存 label。`Value` 的 `Eq` / `Debug` 都只看 `kind`，否则内容相同、来源不同的值不相等。
> - `OriginSite` 是 core 的 `pub(open) trait`：`kind`、`describe(KeyPath)`、`locator`（默认 None）。`label` 只在 `Origin::label()` 里按需生成，不反解析。
> - `KeyPath` 是结构化的段数组（`["db", "port"]`），点号串只在 `origin_of` / `get_path` 的 API 边界解析一次；`origins()` 遍历时直接拼路径。
> - `Source::collect` 返回 `Layer { value, origin }`，一层的值和它的 site 一起产出；`Source::kind` 给 `ByKind` 排序用，不用先 `collect`。
> - 环境变量、命令行整层共用一个 site，site 里存「路径 → 原始变量名/参数名」的索引；`describe(path)` 查表。`Value` 不再按叶子存字符串。
> - `MemorySource` 返回独立的 `MemorySite`，不返回自己：native 默认的引用计数（`MOONBIT_TRIAL_DELETION=0`）不回收环，`MemorySource → Value → &MemorySource` 会漏。JS / wasm-gc 的 tracing GC 不受影响。
> - `Value::with_origin(&OriginSite)` 留给组合来源（一个来源里读多个文件），按子树标不同的 site；`attach_origin` 只补 `None`，不覆盖已有的。
> - `&T` 在 MoonBit 里是 trait object，只能用于 trait，不是 Rust 的借用：没有生命周期检查，trait object 会被 GC/RC 保活。`&Path` 不成立，`Path` 是 struct。
> - `SourceId` 枚举方案没有采用：每个分支仍要存 String，Env/Cli 仍要按路径查名字；trait object 的 site 同时解决这两件事。
> - `ConfigError::MergeConflict` 目前没有代码路径会抛：三种合并规则都是覆盖，不做类型冲突判定。变体先保留，给以后加校验时用。
> - `StringSource` / `BytesSource` 归到 `SourceKind::Custom`，标签分别是 `string` / `bytes`。它们既不是文件，也不是环境变量；给 `ByKind` 一个明确的档位比硬塞进 `Memory` 更清楚。
> - `ByKind(order)` 的数组按优先级从高到低写；没列出的 kind 排在最后。实现上按优先级**从低到高**处理来源，再用 `LastWins` 合并——同一档内后加的仍然赢。
> - `Custom(fn)` 收到的是「已经合好的部分」和「下一层」，返回新的部分。来源已经挂在值上，自定义函数要自己负责保留。
> - `Config::origin_of` / `origins` 保留 `raise ConfigError`：没 `build()` 时它们会现场合并，来源解析失败必须报出来，不能吞掉。路径不存在返回 `None`。
> - 取值错误暂时还没带上来源（`TypeMismatch` 仍是三个字段），等错误类型扩展后再补；现在先用 `origin_of` 查。

## 7. 文件、环境变量、命令行三个 source

> **2026-10 实现时定的细节**
>
> - 新增 `ConfigError::IoError(String)`：读不到外部数据（文件、环境变量）和「读到了但解析失败」是两回事，混进 `ParseError` 会让用户去查格式。消息以 `read error:` 开头，带路径或变量名。
> - `FileSource` 的路径就是 `String`，和 `moonbitlang/x/fs` 的接口一致；`FileSource` 同时实现 `OriginSite` 和 `Locator`：`describe` 给文件路径，`locator` 就是它自己，`origin_of` 拿到的 `locator` 调 `read()` 就能重新读出同一份字节。没有另外拍一个平台 `Path` 类型——那会把平台类型带进 core。
> - `@path` 技术上能进 core（试过 `moon test` 和 `js` / `wasm-gc` 都能过），但 `x/path` 自带 native stub 和 platform cfg，会把平台分派拖进 core；`Path` 也只是 `String` 的包装，`@fs` 只收 `String`。所以 core 里保持 `String`；`FileSource` 以后真要做 `join` / `normalize` 再在包内用 `Path`。
> - 环境变量和命令行都不是「字节 + 格式」，类型推断没法交给 `Format`。推断规则放进 core 的 `Value::from_literal`，两个包共用一份：`true` / `false` → `Bool`，整数 → `Int64`（超出范围报错），带小数点或指数 → `Float`，其余 → 字符串。dotenv 的推断没并过来，因为它要按行号报错，合并会丢掉行号。
> - `Config::attach_origin` 只补没有 site 的节点。`EnvSite` / `CliSite` 在 `collect()` 里建好「路径 → 原始名字」索引，整层共用一个 site；表节点也落在这个 site 上，`describe` 查不到时退回 `env:前缀*` / `cli:args`。
> - `EnvSource` 只读指定前缀；`_` 和 `.` 都算层级，名字转小写。标量占了层级名、或两个变量落到同一个路径时报 `ParseError` 并点名两个变量——按 Map 遍历顺序猜赢家会让结果随平台变。变量名排序后才处理，保证同一份环境每次结果一致。
> - 环境变量的大小写冲突在 Windows 上测不出来：系统本身不区分大小写，`set_env_var` 会直接覆盖同名变量。碰撞检测仍在代码里，用白盒测试直接喂 `assign` 验证。
> - `CliSource` 的取值风格必须二选一：`Equals` 只认 `--key=value`，`Separate` 只认 `--key value`，不在一个来源里混用——混着支持会让 `--flag positional` 这种写法没法解释。短选项必须先登记，重复参数用 `with_array` 显式声明，位置参数用 `with_positional` 按「非选项参数」的顺序映射；解析规则和错误边界见 [cli-args.md](../design/cli-args.md)。
> - 命令行标签只写参数名（`cli:--db-password`），不写值：密码不该因为来源追踪漏进日志。
> - 新增的依赖 `moonbitlang/x` 手写进 `moon.mod`，没用 `moon add`（本仓库的约定）。

## 8. `String::compare` 先比长度

> **2026-10 实测：MoonBit 的 `String::compare` 不是字典序，长度不同的字符串先比长度。**
> `String::compare("z", "aa") < 0` 为真；`["db.host", "log.level", "feature.debug"].sort()` 得到
> 按长度递增的顺序，不是字母序。影响：任何「按名字排序」的展示都不能直接依赖 `sort()`，
> 需要字典序时得自己逐字符比较。环境变量的处理顺序只用它保证「确定」，不当作展示顺序。

## 9. 校验

> **2026-10 实现时定的细节**
>
> - 两条路：按键用 `Rule` 规则表，结构体用 `Validate` trait。两者共用 `ConfigError` 和
>   `check_int_range` / `check_string_len`，不各写一套。
> - `validate` 遇错即停，和 `get_*` 一致；`validate_all` 返回 `Array[ConfigError]`，顺序和规则表一致。
> - 必填项不单独做规则：任何规则取不到路径都会报 `MissingKey`，`get_*` / `extract_from` 本身也会报。
> - 未知键只能按键查。`derive(FromJson)` 忽略结构体里没有的字段，也不提供钩子，结构体不知道外面多了什么；
>   `Rule::allowed_keys` 不写就不查，等于开关默认关。递归 strict schema 暂不做。
> - 新增 `InvalidValue(path, 期望约束, 实际)` 和 `UnknownKey(path)`。`actual` 由规则给：类型不符写形状名，
>   长度不符写长度，自定义规则自己决定。密码类字段由规则负责脱敏，错误类型不打印原值。
> - 不给 `get_*` 加范围变体，也不靠 `derive(FromJson)` 自动校验：前者让 API 膨胀，后者拿不到字段名、
>   约束和未知键。校验是显式的一步，调用方自己决定什么时候跑、失败后怎么处理。
> - `Rule` 内部存 `(KeyPath, Value) -> ConfigError?`：组合规则（`allowed_keys`）需要在路径下面再拼一段，
>   只返回一个字符串不够定位到具体的键。`Rule::custom` 仍然只让用户返回 `String?`。

## 10. 浮点加宽与带来源快照

> **2026-10 定稿：默认加宽整数，严格模式单独提供；快照和 `origins()` 共用叶子口径。**
>
> - `get_float` 接受 `Int` 并 `to_double()`：整数可以作为浮点字段的数值加宽，
>   超出 2^53 时按浮点精度近似。反方向（`Float` → 整数）仍报 `TypeMismatch`，不截断。
> - 需要「只收 `Float`」的调用方用 `get_float_strict`。不把严格做成默认，因为 JSON 里的
>   `1` 本来就是合法整数，默认拒绝会很意外；加宽只在 `Int → Float` 一个方向发生。
> - `Config::snapshot()` 返回 `Array[Entry]`，每条带 `path` / `value` / `origin`。表节点递归、
>   数组当叶子，和 `origins()` 用同一套遍历，避免两套「什么算叶子」的口径。
> - `origin` 是 `Origin?`：`Layer::untracked` 的来源没有可报告的对象，导出时保留 `None`，
>   不伪造 label。`origins()` 仍只返回有来源的叶子。
